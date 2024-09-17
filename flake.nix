{
  description = "A Nix-flake-based Node.js development environment";

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.*.tar.gz";
  inputs.foundry.url = "github:shazow/foundry.nix/monthly"; # Use monthly branch for permanent releases

  inputs.flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.tar.gz"; # for shell.nix compatibility

  outputs = { self, nixpkgs, foundry, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs {
          inherit system; overlays = [
          foundry.overlay
          self.overlays.default
        ];
        };
      });
    in
    {
      overlays.default = final: prev: rec {
        nodejs = prev.nodejs;
        yarn = (prev.yarn.override { inherit nodejs; });
      };

      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bashInteractive
            jq
            nodejs
            yarn
            openssl # used by test-node.bash
            foundry-bin
          ];
          shellHook = ''
            yarn install --cwd "$PWD/scripts"
            export PATH="$PWD/scripts/node_modules/.bin:$PATH"
          '';
        };
      });
    };
}
