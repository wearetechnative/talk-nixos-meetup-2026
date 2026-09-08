# The machine. Everything that makes this box a Vaultwarden box lives here —
# nothing about AWS. `elastinix.lib.tf_command` builds this into the live
# configuration and hands its store path to terraform.
{ config, lib, pkgs, tfvars, ... }:

{
  networking.hostName = "vaultwarden";

  # ── the workload ─────────────────────────────────────────────────────────
  elastinix.services.vaultwarden = {
    enable = true;
    # Vaultwarden's own settings (DATABASE_URL, ADMIN_TOKEN, SMTP_*, ...).
    # Delivered out of band — see README. Never a Nix string, so the value
    # never lands in the world-readable store.
    environment_file = "/vaultwarden/vaultwarden.env";
  };

  # Vaultwarden is configured with dbBackend = "postgresql", so it needs one.
  elastinix.services.postgresql = {
    enable = true;
    data_dir = "/data/postgresql";
    # The option is a string, so interpolate the store path rather than
    # passing the derivation itself.
    initial_script = "${pkgs.writeText "vaultwarden-init.sql" ''
      CREATE ROLE vaultwarden LOGIN;
      CREATE DATABASE vaultwarden OWNER vaultwarden;
    ''}";
  };

  # TLS termination + the ACME account. The vhost itself is declared by the
  # vaultwarden module, at vaultwarden.${tfvars.environment_domain}.
  elastinix.services.nginx.enable = true;

  # ── AWS-side integration ElastiNix ships ─────────────────────────────────
  elastinix.services.cloudwatch-agent.enable = true;

  # ── persistence ──────────────────────────────────────────────────────────
  # The vault and the database live on an attached EBS volume, so replacing
  # the instance does not take the data with it. `ebs_volume_id` in terraform
  # attaches it; this mounts it.
  fileSystems."/data" = {
    device = "/dev/disk/by-label/data";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  fileSystems."/vaultwarden" = {
    device = "/data/vaultwarden";
    options = [ "bind" "nofail" ];
  };

  # No system.stateVersion here on purpose: ElastiNix's own base configuration
  # already sets it, and defining it again is a module-system conflict.
}
