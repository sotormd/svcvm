# derived from https://github.com/microvm-nix/microvm.nix
# https://github.com/microvm-nix/microvm.nix/blob/6dab06c1886c80b5bc28276e4879e699c86b3e5e/nixos-modules/host/default.nix
# modified for svcvm

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.microvm) stateDir;
  microvm-cli = pkgs.callPackage ../../pkgs/microvm-cli.nix { inherit stateDir; };
  user = "microvm";
  group = "kvm";
in
{
  boot.kernelModules = [
    # For `type = "tap"` interfaces
    "tap"
  ];

  # create the stateDir for all microvms
  systemd.tmpfiles.rules = [ "d ${stateDir} 755 ${user} ${group} -" ];

  # install the microvm cli
  environment.systemPackages = [ microvm-cli ];

  # create the user
  users.users.${user} = {
    isSystemUser = true;
    inherit group;
  };

  security.pam.loginLimits = [
    {
      domain = user;
      item = "memlock";
      type = "hard";
      value = "infinity";
    }
    {
      domain = user;
      item = "memlock";
      type = "soft";
      value = "infinity";
    }
  ];

  # systemd services for all microvms
  systemd.services =
    builtins.foldl'
      (
        result: name:
        result
        // (
          let
            guestConfig = config.microvm.vms.${name}.config.config;
            runner = guestConfig.microvm.declaredRunner;
          in
          {
            "install-microvm-${name}" = {
              description = "Install microvm '${name}'";
              before = [
                "microvm@${name}.service"
                "microvm-tap-interfaces@${name}.service"
                "microvm-virtiofsd@${name}.service"
                "microvm-set-booted@${name}.service"
              ];
              partOf = [ "microvm@${name}.service" ];
              wantedBy = [ "microvms.target" ];
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "install-microvm-${name}";
              };
              script = ''
                mkdir -p ${stateDir}/${name}
                cd ${stateDir}/${name}
                ln -sTf ${runner} current
                chown -h ${user}:${group} . current
                ln -sTf ${guestConfig.system.build.toplevel} toplevel
              '';
            };
            "microvm@${name}" = {
              path = lib.mkForce [ ];
              serviceConfig.Type = "simple";
              overrideStrategy = "asDropin";
            };
            "microvm-tap-interfaces@${name}" = {
              path = lib.mkForce [ ];
              overrideStrategy = "asDropin";
            };
            "microvm-virtiofsd@${name}" = {
              path = lib.mkForce [ ];
              overrideStrategy = "asDropin";
            };
          }
        )
      )
      {
        "microvm-tap-interfaces@" = {
          description = "Setup microvm '%i' TAP interfaces";
          before = [ "microvm@%i.service" ];
          partOf = [ "microvm@%i.service" ];
          after = [
            "network.target"
            "microvm-set-booted@%i.service"
          ];
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/tap-up";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            SyslogIdentifier = "microvm-tap-interfaces@%i";
            ExecStart = "${stateDir}/%i/current/bin/tap-up";
            ExecStop = "${stateDir}/%i/booted/bin/tap-down";
          };
        };
        "microvm-virtiofsd@" = {
          description = "VirtioFS daemons for microvm '%i'";
          before = [ "microvm@%i.service" ];
          partOf = [ "microvm@%i.service" ];
          after = [
            "local-fs.target"
            "microvm-set-booted@%i.service"
          ];
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/virtiofsd-run";
          serviceConfig = {
            WorkingDirectory = "${stateDir}/%i";
            ExecStart = "${stateDir}/%i/current/bin/virtiofsd-run";
            LimitNOFILE = 1048576;
            NotifyAccess = "all";
            PrivateTmp = "yes";
            Restart = "always";
            RestartSec = "5s";
            SyslogIdentifier = "microvm-virtiofsd@%i";
            Type = "notify";
            KillMode = "mixed";
          };
        };
        "microvm-set-booted@" = {
          description = "Save microvm '%i' booted configuration";
          before = [ "microvm@%i.service" ];
          partOf = [ "microvm@%i.service" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            SyslogIdentifier = "microvm-set-booted@%i";
            WorkingDirectory = "${stateDir}/%i";
            User = user;
            Group = group;
            ExecStop = "${lib.getExe' pkgs.coreutils "rm"} booted";
          };
          script = ''
            rm -f booted
            ln -s $(readlink current) booted
          '';
        };
        "microvm@" = {
          description = "microvm '%i'";
          requires = [
            "microvm-tap-interfaces@%i.service"
            "microvm-virtiofsd@%i.service"
            "microvm-set-booted@%i.service"
          ];
          after = [
            "network.target"
            "systemd-modules-load.service"
            "microvm-tap-interfaces@%i.service"
            "microvm-virtiofsd@%i.service"
            "microvm-set-booted@%i.service"
          ];
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/microvm-run";
          restartIfChanged = false;
          serviceConfig = {
            Type = "simple";
            WorkingDirectory = "${stateDir}/%i";
            ExecStart = "${stateDir}/%i/current/bin/microvm-run";
            ExecStop = "${stateDir}/%i/booted/bin/microvm-shutdown";
            ExecStartPost = [
              "+${pkgs.runtimeShell} -c 'if [ -x ${stateDir}/%i/current/bin/microvm-register ]; then ${stateDir}/%i/current/bin/microvm-register $MAINPID; fi'"
            ];
            ExecStopPost = [
              "+${pkgs.runtimeShell} -c 'if [ -x ${stateDir}/%i/current/bin/microvm-unregister ]; then ${stateDir}/%i/current/bin/microvm-unregister; fi'"
            ];
            TimeoutSec = 150;
            Restart = "always";
            RestartSec = "5s";
            User = user;
            Group = group;
            SyslogIdentifier = "microvm@%i";
            LimitNOFILE = 1048576;
            NotifyAccess = "all";
            LimitMEMLOCK = "infinity";
          };
        };
      }
      (builtins.attrNames config.microvm.vms);

  systemd.targets.microvms = {
    wantedBy = [ "multi-user.target" ];
  };

  # Enable Kernel Same-Page Merging
  hardware.ksm.enable = lib.mkDefault true;
}
