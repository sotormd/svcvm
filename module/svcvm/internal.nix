# internal readOnly options
# should not be modified, everything here is derived

{
  options,
  config,
  lib,
  ...
}:

with lib;
{
  options._internal = {
    user = mkOption {
      description = "svcvm user, provided by host";
      type = types.str;
      readOnly = true;
    };

    group = mkOption {
      description = "svcvm group, provided by host";
      type = types.str;
      readOnly = true;
    };

    name = mkOption {
      description = "svcvm guest name, provided by host";
      type = types.str;
      readOnly = true;
    };

    machineId = mkOption {
      description = ''
        UUID for this svcvm guest, used for:
        - SMBIOS system UUID
        - systemd /etc/machine-id

        Format: 8-4-4-4-12 hex digits (standard UUID format).
      '';
      type = types.str;
      readOnly = true;
    };

    vcpu = mkOption {
      description = "Number of virtual CPU cores";
      type = options.svcvm.vcpu.type;
      readOnly = true;
    };

    mem = mkOption {
      description = "Amount of RAM in megabytes";
      type = options.svcvm.mem.type;
      readOnly = true;
    };

    runner = mkOption {
      description = "Hypervisor runner for this svcvm guest";
      type = types.package;
      readOnly = true;
    };

    declaredRunner = mkOption {
      description = "Generated declared Hypervisor";
      type = types.package;
      readOnly = true;
    };

    scripts = {
      interfaces = mkOption {
        description = "Script snippets for interfaces that end up in the runner package's bin/ directory";
        type = types.attrsOf types.lines;
        readOnly = true;
      };
      shares = mkOption {
        description = "Script snippets for shares that end up in the runner package's bin/ directory";
        type = types.attrsOf types.lines;
        readOnly = true;
      };
    };

    interfaces = mkOption {
      description = "Final list of network TAP interfaces";
      type = options.svcvm.interfaces.type;
      readOnly = true;
    };

    shares = mkOption {
      description = "Final list of shared virtiofs filesystems, including Nix Store";
      type = options.svcvm.shares.type;
      readOnly = true;
    };

    creds = mkOption {
      description = "Final list of key-value pairs of io.systemd.credentials credential files";
      type = options.svcvm.creds.type;
      readOnly = true;
    };

    vsock-cid = mkOption {
      description = "VSOCK address";
      type = options.svcvm.vsock-cid.type;
      readOnly = true;
    };
  };
}
