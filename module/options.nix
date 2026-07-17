{ pkgs, lib, ... }:

{
  options.svcvm = {

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
                default = { };
                type = lib.mkOptionType {
                  name = "Toplevel NixOS config";
                  merge =
                    _loc: defs:
                    (import "${toString pkgs.path}/nixos/lib/eval-config.nix" {
                      modules = [
                        { _file = "module at ${__curPos.file}:${toString __curPos.line}"; }
                        { networking.hostName = "${name}"; }
                        ./svcvm
                      ]
                      ++ (map (x: x.value) defs);
                      prefix = [
                        "svcvm"
                        "vms"
                        name
                        "config"
                      ];
                      extraModules = config.modules;
                      inherit (config) specialArgs;
                      inherit pkgs;
                      system = "x86_64-linux";
                    });
                };
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
              modules = lib.mkOption {
                type = lib.types.listOf lib.types.deferredModule;
                default = [ ];
                description = ''
                  A list of NixOS modules to be merged into
                  the svcvm's system configuration.
                '';
              };
            };
          }
        )
      );
    };
  };
}
