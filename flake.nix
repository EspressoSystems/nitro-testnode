{
  description = "Nix flake for nitro-testnode";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.flake-compat.url = "github:edolstra/flake-compat";
  inputs.flake-compat.flake = false;
  inputs.foundry.url = "github:shazow/foundry.nix/monthly";

  outputs = { flake-utils, nixpkgs, foundry, ... }:
    let
      overlays = [
        foundry.overlay
      ];
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit overlays system;
        };
        shellHook = ''
          export DOCKER_BUILDKIT=1
        ''
        + pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
          # Fix docker-buildx command on OSX. Can we do this in a cleaner way?
          mkdir -p ~/.docker/cli-plugins
          # Check if the file exists, otherwise symlink
          test -f $HOME/.docker/cli-plugins/docker-buildx || ln -sn $(which docker-buildx) $HOME/.docker/cli-plugins
        '';
      in
      {
        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              # Node
              nodejs
              yarn
              nodePackages.typescript-language-server

              # Docker
              docker-compose # provides the `docker-compose` command
              docker-buildx
              docker-credential-helpers # for `docker-credential-osxkeychain` command

              foundry-bin
            ] ++ lib.optionals stdenv.isDarwin [
              darwin.libobjc
              darwin.IOKit
              darwin.apple_sdk.frameworks.CoreFoundation
            ];
            inherit shellHook;
          };
        };
      });
}
