terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # Point this at your own bucket before applying.
  # backend "s3" {}
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

locals {
  name = "vaultwarden-${var.infra_environment}"

  tags = {
    Name        = local.name
    Environment = var.infra_environment
    ManagedBy   = "elastinix"
    Demo        = "nixos-meetup-2026"
  }
}

# ── the AMI ───────────────────────────────────────────────────────────────
# Uploads the Nix-built bootstrap image to S3, imports it as an EBS snapshot
# and registers it as an AMI. Re-uploads (so re-imports, so re-registers) when
# the store path changes.
module "ami" {
  source = "github.com/wearetechnative/terraform-aws-module-elastinix//ami"

  name               = local.name
  bootstrap_img_path = var.ec2_bootstrap_img_path
  infra_environment  = var.infra_environment
  aws_account_id     = var.aws_account_id
}

# ── the machine ───────────────────────────────────────────────────────────
# Launches the AMI, then copies the live configuration onto it over SSM and
# activates it. Changing the NixOS config changes live_config_path, which
# re-runs the deployment without replacing the instance.
module "instance" {
  source = "github.com/wearetechnative/terraform-aws-module-elastinix//instance"

  name              = local.name
  infra_environment = var.infra_environment
  aws_account_id    = var.aws_account_id

  ec2nix_ami_id = module.ami.ami_id
  instance_type = var.instance_type

  # ElastiNix builds the bootstrap image with virtualisation.diskSize = 16 GiB,
  # so the snapshot is 17 GB and the module's 8 GB default is refused by
  # RunInstances. The workload's own data lives on the separate volume below.
  root_initial_size = 20

  availability_zone    = var.availability_zone
  subnet_id            = var.subnet_id
  vpc_id               = var.vpc_id
  iam_instance_profile = aws_iam_instance_profile.vaultwarden.name

  live_config_path = var.ec2_host_live_path
  ssh_id_file      = var.ssh_id_file

  # HTTP is only open so ACME can answer the challenge; HTTPS is the vault.
  # Nothing else is reachable — the deployment itself goes over SSM.
  ingress_rules = [
    {
      name        = "http-acme"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      name        = "https"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
  ]

  associate_public_ip_address = true

  tags = local.tags
}

# ── persistence ───────────────────────────────────────────────────────────
resource "aws_ebs_volume" "data" {
  availability_zone = var.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true
  tags              = merge(local.tags, { Name = "${local.name}-data" })

  lifecycle {
    prevent_destroy = true
  }
}

# Attached here rather than through the module: the module gates its own
# attachment on `count = var.ebs_volume_id != "" ? 1 : 0`, and a count cannot
# depend on a value that does not exist until apply. Attaching it ourselves has
# no such condition to evaluate.
resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdb"
  volume_id   = aws_ebs_volume.data.id
  instance_id = module.instance.instance_id
}

# A stable address, so the DNS record survives replacing the machine.
resource "aws_eip" "vaultwarden" {
  instance = module.instance.instance_id
  domain   = "vpc"
  tags     = local.tags
}

# ── DNS ───────────────────────────────────────────────────────────────────
# The zone is a pet owned elsewhere; the record is ours, and dies with the demo.
data "aws_route53_zone" "primary" {
  name         = var.dns_zone_name
  private_zone = false
}

resource "aws_route53_record" "vaultwarden" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = "vaultwarden.${var.environment_domain}"
  type    = "A"
  ttl     = 60
  records = [aws_eip.vaultwarden.public_ip]
}

# ── backups ───────────────────────────────────────────────────────────────
# The bucket name is derived from the same tfvars the NixOS config reads, so
# neither side hard-codes it and they cannot drift apart.
resource "aws_s3_bucket" "backups" {
  bucket = "vaultwarden-${var.infra_environment}-${var.aws_account_id}-backups"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-dumps"
    status = "Enabled"
    filter {
      prefix = "postgres/"
    }
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# The instance may write its dumps, and nothing else.
resource "aws_iam_role_policy" "backups" {
  name = "${local.name}-backups"
  role = aws_iam_role.vaultwarden.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.backups.arn}/postgres/*"
    }]
  })
}

# ── the secret ────────────────────────────────────────────────────────────
# Declared here so the name is one fact, not two; the VALUE is put in out of
# band and never enters terraform state:
#
#   aws ssm put-parameter --type SecureString --name /vaultwarden/demo/env \
#     --value file://vaultwarden.env
resource "aws_iam_role_policy" "vaultwarden_env" {
  name = "${local.name}-env"
  role = aws_iam_role.vaultwarden.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/vaultwarden/${var.infra_environment}/env"
    }]
  })
}

# ── the instance's own permissions ────────────────────────────────────────
resource "aws_iam_role" "vaultwarden" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

# SSM is how the deployment reaches the machine — no public SSH needed.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.vaultwarden.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.vaultwarden.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "vaultwarden" {
  name = "${local.name}-profile"
  role = aws_iam_role.vaultwarden.name
  tags = local.tags
}
