{ config, lib, ... }:

{
  options.svcvm = with lib; {
    kernel = mkOption {
      description = "Kernel package to use for svcvm runners. Better set `boot.kernelPackages` instead.";
      default = config.boot.kernelPackages.kernel;
      defaultText = literalExpression ''"''${config.boot.kernelPackages.kernel}"'';
      type = types.package;
    };

    initrd = mkOption {
      description = "Path to the initrd file in the initrd package";
      default = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";
      defaultText = literalExpression ''"''${config.system.build.initialRamdisk}/''${config.system.boot.loader.initrdFile}"'';
      type = types.path;
    };

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
      description = "Network TAP interfaces (with vhost_net)";
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
                MAC address of the guest's network interface
              '';
            };
          };
        });
    };

    shares = mkOption {
      description = "Shared virtiofs directory trees";
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

    vsock.cid = mkOption {
      default = null;
      type = with types; nullOr int;
      description = ''
        Virtual Machine address;
        setting it enables AF_VSOCK

        The following are reserved:
        - 0: Hypervisor
        - 1: Loopback
        - 2: Host
      '';
    };

    kernelParams = mkOption {
      type = with types; listOf str;
      description = "Includes boot.kernelParams but doesn't end up in toplevel, thereby allowing references to toplevel";
    };

    runner = mkOption {
      description = "Generated Hypervisor runner for this NixOS";
      type = with types; attrsOf package;
    };

    declaredRunner = mkOption {
      description = "Generated declared Hypervisor";
      type = types.package;
      default = config.svcvm.runner.qemu;
      defaultText = literalExpression ''"config.svcvm.runner.qemu"'';
    };

    binScripts = mkOption {
      description = ''
        Script snippets that end up in the runner package's bin/ directory
      '';
      default = { };
      type = with types; attrsOf lines;
    };

    creds = mkOption {
      type = with types; attrsOf path;
      default = { };
      description = ''
        Key-value pairs of credential files that will be loaded into the vm using systemd's io.systemd.credential feature.
      '';
      example = literalExpression /* nix */ ''
        {
          SOPS_AGE_KEY = "/run/secrets/guest_svcvm_age_key";
        }
      '';
    };
  };
}
