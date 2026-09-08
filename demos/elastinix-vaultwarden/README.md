# Demo: Vaultwarden on AWS, with ElastiNix

The first demo of the talk: one EC2 instance running
[Vaultwarden](https://github.com/dani-garcia/vaultwarden), where the NixOS
machine *and* the AWS infrastructure come out of a single command.

> **This creates real, billable AWS resources** (an S3 bucket and a ~2 GB
> upload, an EBS snapshot, an AMI, an EBS volume, an Elastic IP and an
> instance). Every account-specific value below is a placeholder you must
> replace; `demo.tfvars.json` will not apply as committed.

## Layout

| Path | What it is |
| --- | --- |
| `flake.nix` | the three commands: `demoPlan`, `demoApply`, `demoDestroy` |
| `nix/hostconf.nix` | the machine — Vaultwarden, Postgres, nginx. Nothing about AWS |
| `nix/authorized_keys.nix` | break-glass root keys baked into the bootstrap image |
| `infra_environments/demo/` | the environment: account, region, domain, subnet |
| `terraform/` | the AWS side: AMI, instance, volume, address, IAM |

## The whole trick

`elastinix.lib.tf_command` builds two things in Nix and hands them to Terraform
as **store paths**:

```sh
export TF_VAR_ec2_bootstrap_img_path="${bootstrapImage}/nixos_image.vhd"
export TF_VAR_ec2_host_live_path="${liveConfig...system.build.toplevel}"
terraform apply -var-file=demo.tfvars.json
```

The bootstrap image goes to S3, is imported as an EBS snapshot and registered
as an AMI. The live configuration is copied onto the running instance over
**SSM** and activated — no public SSH. Change one line in `hostconf.nix` and
the store path changes, so Terraform sees a diff and redeploys the
configuration without replacing the machine.

## Before you apply

1. **Fill in `infra_environments/demo/demo.tfvars.json`** — account id, region,
   VPC and subnet, availability zone, and the domain you control. Vaultwarden
   is served at `vaultwarden.<environment_domain>`, and nginx will ask Let's
   Encrypt for a certificate for exactly that name.
2. **Put your SSH public key in `nix/authorized_keys.nix`**, and point
   `ssh_id_file` at the matching private key.
3. **Create the Vaultwarden environment file out of band.** The module reads
   `/vaultwarden/vaultwarden.env`; it holds `DATABASE_URL`, `ADMIN_TOKEN` and
   any SMTP settings. It is deliberately *not* Nix-managed: a value written in
   Nix lands in the world-readable store.

## Run it

```sh
nix run .#demoPlan
nix run .#demoApply
```

Then point `vaultwarden.<environment_domain>` at the `public_ip` output and
open `https://vaultwarden.<environment_domain>/`.

```sh
nix run .#demoDestroy
```

The EBS data volume carries `prevent_destroy`, so a destroy stops rather than
silently taking the vault with it. Remove that block deliberately when you mean
it.

## What survives a redeploy

- `/data` is a separate **EBS volume** — Postgres and the vault live there
- the address is an **Elastic IP**, so DNS does not churn when the machine goes
- the AMI is re-registered only when the *bootstrap* image changes; ordinary
  configuration changes are an SSM deployment onto the running instance

## The Nivis version of this demo

The same workload, without the Terraform module, is
`020_vaultwarden_ec2` in
[nivis-demos](https://github.com/nivis-project/nivis-demos).
