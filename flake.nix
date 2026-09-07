{
  description = "ElastiNix & Nivis — NixOS Meetup 2026: slides and demos";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.quarto pkgs.texliveMedium pkgs.entr ];
          shellHook = ''
            echo "slides dev shell — quarto $(quarto --version)"
            echo "  ./RUNME.sh install_deps                       fetch the branding extensions"
            echo "  ./RUNME.sh render_auto talk-*.qmd             re-render on change"
            echo "  nix run .#render                              render the deck"
          '';
        };
      });

      # Impure on purpose: renders in the working tree, where
      # ./RUNME.sh install_deps has put _extensions/.
      packages = forAllSystems (pkgs: {
        render = pkgs.writeShellApplication {
          name = "render-slides";
          runtimeInputs = [ pkgs.quarto pkgs.texliveMedium ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root"
            if [ ! -d _extensions ]; then
              echo "render: _extensions/ missing — run ./RUNME.sh install_deps first" >&2
              exit 1
            fi
            for talk in talk-*.qmd; do
              echo "==> rendering $talk"
              quarto render "$talk"
            done
          '';
        };
        default = self.packages.${pkgs.stdenv.hostPlatform.system}.render;
      });
    };
}
