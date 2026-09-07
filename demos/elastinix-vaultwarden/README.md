# Demo: Vaultwarden on AWS, with ElastiNix

> **Status: work in progress.** The demo shown in the talk lives here.

The first demo of the talk: a single EC2 instance running
[Vaultwarden](https://github.com/dani-garcia/vaultwarden), deployed with
[ElastiNix](https://github.com/wearetechnative/elastinix) — the NixOS machine
*and* the AWS infrastructure from one command.

## What the talk shows

1. **The flake** — `elastinix.lib.tf_command`, and the environment's `tfvars.json`
2. **The host config** — the NixOS module that makes this machine a Vaultwarden box
3. **The deploy** — `nix run .#nonProdApply`
4. **Backups**
5. **Load balancer, or not** — code only, not applied

## How it works

`elastinix.lib.tf_command` builds two things in Nix and hands them to Terraform
as store paths:

```sh
export TF_VAR_ec2_bootstrap_img_path="${bootstrapImage}/nixos_image.vhd"
export TF_VAR_ec2_host_live_path="${liveConfig...system.build.toplevel}"
terraform apply -var-file=<env>.tfvars.json
```

The bootstrap image is uploaded to S3, imported as an EBS snapshot and registered
as an AMI; the live configuration is copied onto the running instance over SSM.
Change one line of NixOS config and the store path changes, so Terraform sees a
diff.

The Nivis counterpart of this demo — the same stack, without the Terraform module
— is in [nivis-demos](https://github.com/nivis-project/nivis-demos).
