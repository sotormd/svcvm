{
  description = "service virtual machines for NixOS (stripped down from microvm-nix: https://github.com/microvm-nix/microvm.nix)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    inputs:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs { inherit system; };
    in
    {
      packages.${system}.svcvm = pkgs.callPackage ./pkgs/svcvm-cli.nix { };
      apps.${system}.svcvm = {
        program = "${inputs.self.packages.${system}.svcvm}/bin/svcvm";
        type = "app";
      };
      nixosModules = {
        host = ./nixos-modules/host;
        microvm = ./nixos-modules/microvm;
      };
    };
}
