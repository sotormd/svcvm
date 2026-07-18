# general system configuration

{ config, lib, ... }:

let
  inherit (config._internal) name machineId;
in
{
  # svcvm guest name
  networking.hostName = name;

  # generate machineId
  _internal.machineId =
    let
      hash = builtins.hashString "sha256" "svcvm:(microvm.nix):${name}";
      hs = offset: len: builtins.substring offset len hash;
    in
    builtins.concatStringsSep "-" [
      (hs 0 8)
      (hs 8 4)
      (hs 12 4)
      (hs 16 4)
      (hs 20 12)
    ];

  # set machineId
  environment.etc."machine-id".text = lib.replaceString "-" "" machineId + "\n";
  networking.hostId = lib.mkDefault (builtins.substring 0 8 machineId);

  # vcpus and memory
  _internal.vcpu = config.svcvm.vcpu;
  _internal.mem = config.svcvm.mem;

  # nixos enables grub by default, we dont need it
  boot.loader.grub.enable = false;

  # kernel modules we require
  boot.initrd.kernelModules = [
    "virtio_mmio"
    "virtio_pci"
    "virtio_blk"
    "virtiofs"
  ];

  # modules that consume boot time but have rare use-cases
  boot.blacklistedKernelModules = [
    "rfkill"
    "intel_pstate"
    "drm"
  ];

  # use systemd initrd for startup speed
  boot.initrd.systemd.enable = lib.mkDefault true;

  # we only need one kernel console
  boot.kernelParams = [ "8250.nr_uarts=1" ];

  # not required
  boot.swraid.enable = lib.mkDefault false;

  # due to a bug in systemd-networkd: https://github.com/systemd/systemd/issues/29388
  # we cannot use systemd-networkd-wait-online.
  systemd.network.wait-online.enable = lib.mkDefault false;

  # not required
  boot.initrd.systemd.tpm2.enable = lib.mkDefault false;
  systemd.tpm2.enable = lib.mkDefault false;

  # consumes a lot of boot time
  systemd.services.mount-pstore.enable = false;

  # fails in normal usage
  systemd.generators.systemd-gpt-auto-generator = "/dev/null";

  # documentation is huge
  documentation.enable = lib.mkDefault false;

  # networkd is used due to some strange startup time issues with nixos's
  # homegrown dhcp implementation
  networking.useNetworkd = lib.mkDefault true;

  # no need for the nix package manager
  # this is later enforced by assertions
  nix.enable = lib.mkDefault false;

  # no need to enable switch-to-configuration.pl
  system.switch.enable = lib.mkDefault false;
}
