{
  config,
  lib,
  pkgs,
  ...
}:

let
  qemu =
    {
      pkgs,
      microvmConfig,
      linuxTarget,
      ...
    }:

    let
      inherit (pkgs) lib;

      vmHostPackages = pkgs;

      # use QEMU/KVM for hardware-accelerated microvms
      qemu = vmHostPackages.qemu_kvm;

      inherit (microvmConfig)
        hostName
        machineId
        vcpu
        mem
        interfaces
        shares
        vsock
        kernel
        initrd
        creds
        ;

      # svcvm socket name
      socket = "${hostName}.sock";

      arch = "x86_64";

      machine = "microvm";

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

      machineConfig = builtins.concatStringsSep "," (
        [ machine ] ++ map (name: "${name}=${machineOpts.${name}}") (builtins.attrNames machineOpts)
      );

      enumerate =
        n: xs:
        if xs == [ ] then
          [ ]
        else
          [
            (builtins.head xs // { index = n; })
          ]
          ++ (enumerate (n + 1) (builtins.tail xs));

      tapMultiQueue = vcpu > 1;

      writeQmp = data: ''
        echo '${builtins.toJSON data}'
      '';

      kernelConsole = "earlyprintk=ttyS0 console=ttyS0";

      systemdCredentialStrings = lib.mapAttrsToList (
        name: path: "name=opt/io.systemd.credentials/${name},file=${path}"
      ) creds;
      fwCfgOptions = systemdCredentialStrings;

    in
    lib.warnIf (mem == 2048)
      ''
        QEMU hangs if memory is exactly 2GB

        <https://github.com/microvm-nix/microvm.nix/issues/171>
      ''
      {
        inherit tapMultiQueue;

        command =
          lib.escapeShellArgs [
            "${qemu}/bin/qemu-system-${arch}"
            "-name"
            hostName
            "-M"
            machineConfig
            "-m"
            "${toString mem}M"
            "-smp"
            (toString vcpu)
            "-nodefaults"
            "-no-user-config"
            "-no-reboot"

            "-kernel"
            "${kernel.out}/${linuxTarget}"
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
            "${kernelConsole} reboot=t panic=-1 ${toString microvmConfig.kernelParams}"

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
                  "socket,id=fs${toString index},path=${hostName}-virtiofs-${tag}.sock"
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
            ++ lib.optionals (vsock.cid != null) [
              "-device"
              "vhost-vsock-pci,guest-cid=${toString vsock.cid}"
            ]
          );

        shutdownCommand = ''
          # Exit gracefully if QEMU is already gone (e.g., killed by machinectl)
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
          ${vmHostPackages.socat}/bin/socat STDIO UNIX:${socket},shut-none
        '';
      };

  buildRunner =
    {
      pkgs,
      microvmConfig,
      toplevel,
    }:

    let
      inherit (pkgs) lib;

      inherit (microvmConfig) hostName;

      vmHostPackages = pkgs;

      linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;

      hypervisorConfig = qemu {
        inherit
          pkgs
          microvmConfig
          linuxTarget
          ;
      };

      inherit (hypervisorConfig) command shutdownCommand;
      tapMultiQueue = hypervisorConfig.tapMultiQueue or false;

      execArg = ''-a "svcvm@${hostName}"'';

      binScripts = microvmConfig.binScripts // {
        microvm-run = ''
          set -eou pipefail
          exec ${execArg} ${command}
        '';
        microvm-shutdown = shutdownCommand;
      };

      binScriptPkgs = lib.mapAttrs (
        scriptName: lines: vmHostPackages.writeShellScript "svcvm-qemu-${scriptName}" lines
      ) binScripts;
    in

    vmHostPackages.buildPackages.runCommand "svcvm-qemu-${hostName}"
      {
        # for `nix run`
        meta.mainProgram = "microvm-run";
        passthru = { inherit tapMultiQueue; };
      }
      ''
        mkdir -p $out/bin

        ${lib.concatMapStrings (scriptName: ''
          ln -s ${binScriptPkgs.${scriptName}} $out/bin/${scriptName}
        '') (builtins.attrNames binScriptPkgs)}

        mkdir -p $out/share/svcvm
        ln -s ${toplevel} $out/share/svcvm/system

        echo vnet_hdr > $out/share/svcvm/tap-flags
        ${lib.optionalString tapMultiQueue ''
          echo multi_queue >> $out/share/svcvm/tap-flags
        ''}
        ${lib.concatMapStringsSep " " (
          interface:
          lib.optionalString (interface ? id) ''
            echo "${interface.id}" >> $out/share/svcvm/tap-interfaces
          ''
        ) microvmConfig.interfaces}

        ${lib.concatMapStrings (
          { tag, ... }:
          ''
            mkdir -p $out/share/svcvm/virtiofs/${tag}
            echo "${hostName}-virtiofs-${tag}.sock" > $out/share/svcvm/virtiofs/${tag}/socket
            echo "${hostName}-virtiofs-${tag}.sock" > $out/share/svcvm/virtiofs/${tag}/source
          ''
        ) microvmConfig.shares}

        # VSOCK info for ssh access
        ${lib.optionalString (microvmConfig.vsock.cid != null) ''
          echo "${toString microvmConfig.vsock.cid}" > $out/share/svcvm/vsock-cid
        ''}

        echo "qemu" > $out/share/svcvm/hypervisor
      '';

  inherit (config.networking) hostName;

  machineId =
    let
      hash = builtins.hashString "sha256" "svcvm:(microvm.nix):${hostName}";
      hs = offset: len: builtins.substring offset len hash;
    in
    builtins.concatStringsSep "-" [
      (hs 0 8)
      (hs 8 4)
      (hs 12 4)
      (hs 16 4)
      (hs 20 12)
    ];

  microvmConfig = config.svcvm // {
    inherit hostName machineId;
  };

  inherit (config.system.build) toplevel;
in

{
  imports = [
    ./options.nix
    ./asserts.nix
    ./system.nix
    ./mounts.nix
    ./interfaces.nix
    ./virtiofsd
  ];

  config = {
    svcvm.runner.qemu = buildRunner { inherit pkgs microvmConfig toplevel; };
    environment.etc."machine-id".text = lib.replaceString "-" "" machineId + "\n";
    networking.hostId = lib.mkDefault (builtins.substring 0 8 machineId);
  };
}
