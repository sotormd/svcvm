{ config, lib, ... }:

{
  boot = {
    loader.grub.enable = false;
    initrd.kernelModules = [
      "virtio_mmio"
      "virtio_pci"
      "virtio_blk"
      "virtiofs"
    ];

    blacklistedKernelModules = [
      "rfkill"
      "intel_pstate"
      "drm"
    ];

    initrd.systemd = {
      enable = lib.mkDefault true;
      tpm2.enable = lib.mkDefault false;
    };
    kernelParams = [ "8250.nr_uarts=1" ];
    swraid.enable = lib.mkDefault false;
  };

  systemd = {
    network.wait-online.enable = lib.mkDefault false;
    tpm2.enable = lib.mkDefault false;
    services.mount-pstore.enable = false;
    generators.systemd-gpt-auto-generator = "/dev/null";
  };

  svcvm.kernelParams = config.boot.kernelParams ++ [ "init=${config.system.build.toplevel}/init" ];

  documentation.enable = lib.mkDefault false;

  networking.useNetworkd = lib.mkDefault true;

  # no need for the nix package manager
  # this is later enforced by assertions
  nix.enable = lib.mkDefault false;

  # no need to enable switch-to-configuration.pl
  system.switch.enable = lib.mkDefault false;
}
