# svcvm hypervisor runner

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config._internal)
    name
    machineId
    vcpu
    mem
    scripts
    interfaces
    shares
    creds
    vsock-cid
    ;

  # helpers
  enumerate =
    n: xs:
    if xs == [ ] then
      [ ]
    else
      [
        (builtins.head xs // { index = n; })
      ]
      ++ (enumerate (n + 1) (builtins.tail xs));

  writeQmp = data: ''
    echo '${builtins.toJSON data}'
  '';

  # use QEMU/KVM for hardware-acceleration
  qemu-pkg = pkgs.qemu_kvm;

  # qemu architecture
  arch = "x86_64";

  # qemu machine type
  machine = "microvm";

  # qemu machine options
  machineOpts = {
    accel = "kvm:tcg";
    mem-merge = "on";
    acpi = "on";
    pit = "off";
    pic = "off";
    pcie = "on";
    rtc = "on";
    usb = "off";
  };

  # final qemu machine configuration
  machineConfig = builtins.concatStringsSep "," (
    [ machine ] ++ map (name: "${name}=${machineOpts.${name}}") (builtins.attrNames machineOpts)
  );

  # svcvm guest socket
  socket = "${name}.sock";

  # whether to enable multi-queue TAP
  tapMultiQueue = vcpu > 1;

  # io.systemd.credentials strings
  systemdCredentialStrings = lib.mapAttrsToList (
    name: path: "name=opt/io.systemd.credentials/${name},file=${path}"
  ) creds;
  fwCfgOptions = systemdCredentialStrings;

  # kernel
  kernel = "${config.boot.kernelPackages.kernel.out}/${pkgs.linux.target}";

  # initrd path
  initrd = "${config.system.build.initialRamdisk}/${config.system.boot.loader.initrdFile}";

  # final kernel params, not included in toplevel - so can refer to it
  kernelParams = config.boot.kernelParams ++ [ "init=${config.system.build.toplevel}/init" ];

  # kernel console
  kernelConsole = "earlyprintk=ttyS0 console=ttyS0";

  # final qemu command
  qemu-command =
    lib.escapeShellArgs [
      "${qemu-pkg}/bin/qemu-system-${arch}"

      "-name"
      name

      "-M"
      machineConfig

      "-m"
      "${toString mem}M"
      "-smp"
      "${toString vcpu}"

      "-nodefaults"
      "-no-user-config"
      "-no-reboot"

      "-kernel"
      kernel
      "-initrd"
      initrd

      "-chardev"
      "stdio,id=stdio,signal=off"
      "-device"
      "virtio-rng-pci"
      "-smbios"
      "type=1,uuid=${machineId}"

      "-serial"
      "chardev:stdio"

      "-enable-kvm"

      "-cpu"
      "host,+x2apic,-sgx"

      "-device"
      "i8042"

      "-append"
      "${kernelConsole} reboot=t panic=-1 ${toString kernelParams}"

      "-nographic"

      "-sandbox"
      "on"

      "-qmp"
      "unix:${socket},server,nowait"
    ]
    + " "
    + lib.escapeShellArgs (
      builtins.concatMap (fwCfgOption: [
        "-fw_cfg"
        fwCfgOption
      ]) fwCfgOptions
      ++ lib.optionals (shares != [ ]) (
        [
          "-numa"
          "node,memdev=mem"
          "-object"
          "memory-backend-memfd,id=mem,size=${toString mem}M,share=on"
        ]
        ++ builtins.concatMap (
          { index, tag, ... }:
          [
            "-chardev"
            "socket,id=fs${toString index},path=${name}-virtiofs-${tag}.sock"
            "-device"
            "vhost-user-fs-pci,chardev=fs${toString index},tag=${tag}"
          ]
        ) (enumerate 0 shares)
      )
      ++ (builtins.concatMap (
        { id, mac, ... }:
        [
          "-netdev"
          (lib.concatStringsSep "," (
            [
              "tap"
              "id=${id}"
              "ifname=${id}"
              "script=no"
              "downscript=no"
              "vhost=on"
            ]
            ++ lib.optionals tapMultiQueue [
              "queues=${toString vcpu}"
            ]
          ))
          "-device"
          "virtio-net-pci,netdev=${id},mac=${mac}"
        ]
      ) interfaces)
      ++ lib.optionals (vsock-cid != null) [
        "-device"
        "vhost-vsock-pci,guest-cid=${toString vsock-cid}"
      ]
    );

  # guest shutdown command
  shutdownCommand = ''
    # exit gracefully if QEMU is already gone
    if [ ! -S ${socket} ]; then
      exit 0
    fi

    (
      ${writeQmp { execute = "qmp_capabilities"; }}
      ${writeQmp {
        execute = "input-send-event";
        arguments.events = [
          {
            type = "key";
            data = {
              down = true;
              key = {
                type = "qcode";
                data = "ctrl";
              };
            };
          }
          {
            type = "key";
            data = {
              down = true;
              key = {
                type = "qcode";
                data = "alt";
              };
            };
          }
          {
            type = "key";
            data = {
              down = true;
              key = {
                type = "qcode";
                data = "delete";
              };
            };
          }
        ];
      }}
       # wait for exit
      cat
    ) | \
    ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none
  '';

  # pretty name while executing
  execArg = ''-a "svcvm@${name}"'';

  # final binScripts
  binScripts = {
    svcvm-run = ''
      set -eou pipefail
      exec ${execArg} ${qemu-command}
    '';
    svcvm-shutdown = shutdownCommand;
  }
  // scripts.interfaces
  // scripts.shares;

  binScriptPkgs = lib.mapAttrs (
    scriptName: lines: pkgs.writeShellScript "svcvm-qemu-${scriptName}" lines
  ) binScripts;

  # final runner
  buildRunner = pkgs.buildPackages.runCommand "svcvm-qemu-${name}" { } ''
    mkdir -p $out/bin

    ${lib.concatMapStrings (scriptName: ''
      ln -s ${binScriptPkgs.${scriptName}} $out/bin/${scriptName}
    '') (builtins.attrNames binScriptPkgs)}

    mkdir -p $out/share/svcvm
    ln -s ${config.system.build.toplevel} $out/share/svcvm/system

    echo vnet_hdr > $out/share/svcvm/tap-flags
    ${lib.optionalString tapMultiQueue ''
      echo multi_queue >> $out/share/svcvm/tap-flags
    ''}
    ${lib.concatMapStringsSep " " (
      interface:
      lib.optionalString (interface ? id) ''
        echo "${interface.id}" >> $out/share/svcvm/tap-interfaces
      ''
    ) interfaces}

    ${lib.concatMapStrings (
      { tag, ... }:
      ''
        mkdir -p $out/share/svcvm/virtiofs/${tag}
        echo "${name}-virtiofs-${tag}.sock" > $out/share/svcvm/virtiofs/${tag}/socket
        echo "${name}-virtiofs-${tag}.sock" > $out/share/svcvm/virtiofs/${tag}/source
      ''
    ) shares}

    # VSOCK info for ssh access
    ${lib.optionalString (vsock-cid != null) ''
      echo "${toString vsock-cid}" > $out/share/svcvm/vsock-cid
    ''}

    echo "qemu" > $out/share/svcvm/hypervisor
  '';
in
{
  _internal.runner = buildRunner;
}
