# Supplied from infra_environments/<env>/<env>.tfvars.json via -var-file.
variable "aws_account_id" { type = string }
variable "aws_region" { type = string }
variable "infra_environment" { type = string }
variable "environment_domain" { type = string }
variable "instance_type" { type = string }
variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "availability_zone" { type = string }
variable "ssh_id_file" { type = string }

# The Route 53 zone this demo writes its record into. The zone itself is NOT
# ours: it is owned by nivis-demos `010_dns`, because a zone outlives every
# machine that answers to it. We look it up by name — the catstack data-block
# answer — so neither stack reads the other's state.
variable "dns_zone_name" { type = string }

# Set by Nix. `elastinix.lib.tf_command` exports these as TF_VAR_… before
# calling terraform, so their values are store paths: change one line of NixOS
# config and the path changes, and terraform sees a diff.
variable "ec2_bootstrap_img_path" { type = string }
variable "ec2_host_live_path" { type = string }
