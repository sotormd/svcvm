# derived from https://github.com/microvm-nix/microvm
# https://github.com/microvm-nix/microvm.nix/blob/6dab06c1886c80b5bc28276e4879e699c86b3e5e/nixos-modules/host/options.nix
# modified for svcvm

{ pkgs, lib, ... }:

{
  options.microvm = {

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/svcvms";
      description = ''
        Directory that contains the svcvms.
      '';
    };

    vms = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, name, ... }: {
            options = {
              config = lib.mkOption {
                description = ''
                  A specification of the desired configuration of this svcvm,
                  as a NixOS module.
                '';
                type = lib.mkOptionType {
                  name = "Toplevel NixOS config";
                  merge =
                    _loc: defs:
                    (import "${toString config.nixpkgs}/nixos/lib/eval-config.nix" {
                      modules = [
                        { _file = "module at ${__curPos.file}:${toString __curPos.line}"; }
                        { networking.hostName = name; }
                        ../microvm
                      ]
                      ++ (map (x: x.value) defs);
                      prefix = [
                        "microvm"
                        "vms"
                        name
                        "config"
                      ];
                      inherit (config) extraModules specialArgs pkgs;
                      system =
                        if config.pkgs != null then
                          config.pkgs.stdenv.hostPlatform.system
                        else
                          pkgs.stdenv.hostPlatform.system;
                    });
                };
              };
              nixpkgs = lib.mkOption {
                type = lib.types.path;
                default = if config.pkgs != null then config.pkgs.path else pkgs.path;
                description = ''
                  The nixpkgs path to use for the MicroVM. Defaults to the
                  host's nixpkgs.
                '';
              };
              pkgs = lib.mkOption {
                type = lib.types.nullOr lib.types.unspecified;
                default = pkgs;
                description = ''
                  The package set to use for the svcvm. Must be a
                  nixpkgs package set with the microvm overlay. Determines
                  the system of the MicroVM.

                  If set to null, a new package set will be instantiated.
                '';
              };
              specialArgs = lib.mkOption {
                type = lib.types.attrsOf lib.types.unspecified;
                default = { };
                description = ''
                  A set of special arguments to be passed to NixOS modules.
                  This will be merged into the `specialArgs` used to evaluate
                  the NixOS configurations.
                '';
              };
              extraModules = lib.mkOption {
                type = lib.types.listOf lib.types.deferredModule;
                default = [ ];
                description = ''
                  A list of additional NixOS modules to be merged into
                  the svcvm's system configuration.
                '';
                defaultText = lib.literalExpression ''
                  [
                    flakeInputs..some-project.nixosModules.example
                    flakeInputs.another-project.nixosModules.default
                  ]
                '';
              };
            };
          }
        )
      );
    };
  };
}
