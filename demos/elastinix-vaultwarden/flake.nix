{
  description = "Vaultwarden on AWS EC2, built and deployed with ElastiNix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    elastinix.url = "github:wearetechnative/elastinix/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };

  outputs =
    inputs@{ flake-parts, nixpkgs, elastinix, ... }:

    flake-parts.lib.mkFlake { inherit inputs; } {
      # Systems that can *run* a deployment — not the target's architecture.
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      imports = [ inputs.devshell.flakeModule ];

      perSystem =
        { config, pkgs, ... }:
        let
          runSystem = pkgs.stdenv.hostPlatform.system;

          varsfile_demo = ./infra_environments/demo/demo.tfvars.json;

          machineArgs = {
            inherit nixpkgs;
            # OpenTofu, not Terraform: MPL-2.0 rather than BUSL, and it matches
            # the lock file and the devshell.
            terraformBinConf = {
              distribution = "opentofu";
              version = "1-8-7";
            };
            machineConfig = import ./nix/hostconf.nix;
            targetSystem = "x86_64-linux";
            rootAuthorizedKeys = import ./nix/authorized_keys.nix;
          };
        in
        {
          packages = {
            # `nix run .#demoApply` — builds the bootstrap image and the live
            # config, then hands both to terraform as store paths.
            demoApply = elastinix.lib.tf_command (
              machineArgs // { inherit runSystem; varsfile = varsfile_demo; }
            );

            demoPlan = elastinix.lib.tf_command (
              machineArgs // { inherit runSystem; varsfile = varsfile_demo; cmd = "plan"; }
            );

            demoDestroy = elastinix.lib.tf_command (
              machineArgs // { inherit runSystem; varsfile = varsfile_demo; cmd = "destroy"; }
            );
          };

          devshells.default = {
            packages = [ pkgs.awscli2 pkgs.jq pkgs.opentofu ];
          };
        };
    };
}
