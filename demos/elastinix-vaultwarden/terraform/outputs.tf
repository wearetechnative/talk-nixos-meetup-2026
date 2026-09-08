output "instance_id" {
  value       = module.instance.instance_id
  description = "Deploy target: the SSM session goes to root@<instance_id>."
}

output "public_ip" {
  value       = aws_eip.vaultwarden.public_ip
  description = "Point vaultwarden.<environment_domain> here."
}

output "ami_id" {
  value = module.ami.ami_id
}

output "vault_url" {
  value = "https://vaultwarden.${var.environment_domain}/"
}

output "backup_bucket" {
  value       = aws_s3_bucket.backups.bucket
  description = "Nightly pg_dump lands here; the NixOS config derives the same name."
}
