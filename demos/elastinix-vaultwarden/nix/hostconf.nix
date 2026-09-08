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

  # ── backups ──────────────────────────────────────────────────────────────
  # ElastiNix ships a psqldump service, but it is wired to Twenty CRM. This is
  # the demo's own: a nightly dump to S3.
  #
  # Note where the bucket name comes from — the *same* tfvars the terraform
  # reads. Both sides derive it; neither hard-codes it. That is the single
  # source of truth doing something visible.
  systemd.timers.vaultwarden-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
      Unit = "vaultwarden-backup.service";
    };
  };

  systemd.services.vaultwarden-backup = {
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      # Credentials come from the instance profile, which terraform grants
      # write access to exactly this one bucket.
      ExecStart =
        let
          bucket = "vaultwarden-${tfvars.infra_environment}-${tfvars.aws_account_id}-backups";
          script = pkgs.writeShellScript "vaultwarden-backup" ''
            set -euo pipefail
            stamp="$(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H%M%SZ)"
            ${pkgs.postgresql}/bin/pg_dump vaultwarden \
              | ${pkgs.gzip}/bin/gzip -9 \
              | ${pkgs.awscli2}/bin/aws s3 cp - \
                  "s3://${bucket}/postgres/vaultwarden-$stamp.sql.gz"
          '';
        in
        "${script}";
    };
  };

  # ── the secret ───────────────────────────────────────────────────────────
  # Vaultwarden's environment file (DATABASE_URL, ADMIN_TOKEN, SMTP_*) is put
  # in SSM Parameter Store out of band:
  #
  #   aws ssm put-parameter --type SecureString \
  #     --name /vaultwarden/demo/env --value file://vaultwarden.env
  #
  # and fetched at activation. It never passes through Nix, so it never lands
  # in the world-readable store. Terraform grants this instance read access to
  # exactly this one parameter.
  systemd.services.vaultwarden-env = {
    description = "Fetch the Vaultwarden environment file from SSM";
    wantedBy = [ "vaultwarden.service" ];
    before = [ "vaultwarden.service" ];
    after = [ "network-online.target" "vaultwarden.mount" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0077";
      ExecStart = pkgs.writeShellScript "vaultwarden-env" ''
        set -euo pipefail
        ${pkgs.awscli2}/bin/aws ssm get-parameter \
          --region ${tfvars.aws_region} \
          --name "/vaultwarden/${tfvars.infra_environment}/env" \
          --with-decryption --query Parameter.Value --output text \
          > /vaultwarden/vaultwarden.env
        chmod 0600 /vaultwarden/vaultwarden.env
      '';
    };
  };

  # ── persistence ──────────────────────────────────────────────────────────
  # The vault and the database live on an attached EBS volume, so replacing
  # the instance does not take the data with it. `ebs_volume_id` in terraform
  # attaches it; this makes it usable.
  #
  # NOTE, and this is the honest part: a fresh EBS volume has no filesystem and
  # no label, so it must be formatted once. The tidy way is to address it by
  # its volume id — AWS exposes that as a stable /dev/disk/by-id symlink. But
  # the volume id does not exist until Terraform has created the volume, and
  # ElastiNix has no way to hand that value back to Nix. So this picks the one
  # attached disk that has no filesystem, which is fine for a demo with exactly
  # one data volume and is not what you would ship.
  #
  # Remember this when we get to the roadmap.
  systemd.services.format-data-volume = {
    description = "Create a filesystem on the data volume if it has none";
    wantedBy = [ "data.mount" ];
    before = [ "data.mount" ];
    after = [ "systemd-udev-settle.service" ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "format-data-volume" ''
        set -euo pipefail
        if ${pkgs.util-linux}/bin/blkid -L data >/dev/null 2>&1; then
          echo "data volume already has a filesystem"
          exit 0
        fi
        for dev in /dev/nvme?n1 /dev/xvd[b-z] /dev/sd[b-z]; do
          [ -b "$dev" ] || continue
          # Skip anything that already carries a filesystem or a partition
          # table — that includes the root disk.
          if ${pkgs.util-linux}/bin/blkid "$dev" >/dev/null 2>&1; then continue; fi
          if [ -b "''${dev}p1" ] || [ -b "''${dev}1" ]; then continue; fi
          echo "formatting $dev as the data volume"
          ${pkgs.e2fsprogs}/bin/mkfs.ext4 -L data "$dev"
          exit 0
        done
        echo "no unformatted volume found — nothing to do" >&2
      '';
    };
  };

  fileSystems."/data" = {
    device = "/dev/disk/by-label/data";
    fsType = "ext4";
    options = [ "nofail" ];
  };

  systemd.tmpfiles.rules = [
    "d /data/vaultwarden 0700 vaultwarden vaultwarden -"
    "d /data/postgresql  0700 postgres    postgres    -"
  ];

  fileSystems."/vaultwarden" = {
    device = "/data/vaultwarden";
    options = [ "bind" "nofail" ];
  };

  # No system.stateVersion here on purpose: ElastiNix's own base configuration
  # already sets it, and defining it again is a module-system conflict.
}
