{ config, lib, ... }:

{
  # share host's nix store
  svcvm.shares = [
    {
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
    }
  ];

  fileSystems = lib.mkMerge [
    {
      # a tmpfs /
      "/" = {
        device = "rootfs";
        fsType = "tmpfs";
        options = [ "size=50%,mode=0755" ];
        neededForBoot = true;
      };
      "/nix/store" = {
        device = "/nix/.ro-store";
        fsType = "virtiofs";
        options = [
          "ro"
          "bind"
        ];
        neededForBoot = true;
      };
    }
    (
      # virtiofs shares
      builtins.foldl' (
        result:
        {
          mountPoint,
          tag,
          source,
          ...
        }:
        result
        // {
          "${mountPoint}" = {
            device = tag;
            fsType = "virtiofs";
            options = [
              "defaults"
              "x-systemd.after=systemd-modules-load.service"
            ];
          }
          // lib.optionalAttrs (source == "/nix/store") {
            neededForBoot = true;
          };
        }
      ) { } config.svcvm.shares
    )
  ];

  # fix unmounting in qemu on shutdown for /nix/store
  systemd.mounts = lib.mkIf config.boot.initrd.systemd.enable [
    {
      what = "store";
      where = "/nix/store";
      overrideStrategy = "asDropin";
      unitConfig.DefaultDependencies = false;
    }
  ];
}
