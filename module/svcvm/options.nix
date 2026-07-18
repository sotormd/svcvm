# configurable options

{ lib, ... }:

with lib;
{
  options.svcvm = {
    vcpu = mkOption {
      description = "Number of virtual CPU cores";
      default = 1;
      type = types.ints.positive;
    };

    mem = mkOption {
      description = "Amount of RAM in megabytes";
      default = 512;
      type = types.ints.positive;
    };

    interfaces = mkOption {
      description = "Network TAP interfaces";
      default = [ ];
      type =
        with types;
        listOf (submodule {
          options = {
            id = mkOption {
              type = str;
              description = ''
                Interface name on the host
              '';
            };
            mac = mkOption {
              type = str;
              description = ''
                MAC address of the svcvm guest's network interface
              '';
            };
          };
        });
    };

    shares = mkOption {
      description = "Shared virtiofs filesystems";
      default = [ ];
      type =
        with types;
        listOf (submodule {
          options = {
            tag = mkOption {
              type = str;
              description = "Unique virtiofs daemon tag";
            };
            source = mkOption {
              type = nonEmptyStr;
              description = "Path to shared directory tree";
            };
            mountPoint = mkOption {
              type = path;
              description = "Where to mount the share inside the container";
            };
            readOnly = mkOption {
              type = bool;
              default = false;
              description = "Turn off write access";
            };
          };
        });
    };

    creds = mkOption {
      description = "Key-value pairs of credential files that will be loaded into the svcvm guest using systemd's io.systemd.credential feature";
      default = { };
      type = with types; attrsOf path;
    };

    vsock-cid = mkOption {
      description = ''
        VSOCK address;
        setting it enables AF_VSOCK

        The following are reserved:
        - 0: Hypervisor
        - 1: Loopback
        - 2: Host
      '';
      default = null;
      type = with types; nullOr int;
    };
  };
}
