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
  svcvm-cli = pkgs.callPackage ../../pkgs/svcvm-cli.nix { inherit stateDir; };
  user = "svcvm";
  group = "kvm";
in
{
  boot.kernelModules = [
    # For `type = "tap"` interfaces
    "tap"
  ];

  # create the stateDir for all svcvms
  systemd.tmpfiles.rules = [ "d ${stateDir} 755 ${user} ${group} -" ];

  # install the svcvm cli
  environment.systemPackages = [ svcvm-cli ];

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

  # systemd services for all svcvms
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
            "install-svcvm-${name}" = {
              description = "Install svcvm '${name}'";
              before = [
                "svcvm@${name}.service"
                "svcvm-tap-interfaces@${name}.service"
                "svcvm-virtiofsd@${name}.service"
                "svcvm-set-booted@${name}.service"
              ];
              partOf = [ "svcvm@${name}.service" ];
              wantedBy = [ "svcvms.target" ];
              serviceConfig = {
                Type = "oneshot";
                SyslogIdentifier = "install-svcvm-${name}";
              };
              script = ''
                mkdir -p ${stateDir}/${name}
                cd ${stateDir}/${name}
                ln -sTf ${runner} current
                chown -h ${user}:${group} . current
                ln -sTf ${guestConfig.system.build.toplevel} toplevel
              '';
            };
            "svcvm@${name}" = {
              path = lib.mkForce [ ];
              serviceConfig.Type = "simple";
              overrideStrategy = "asDropin";
            };
            "svcvm-tap-interfaces@${name}" = {
              path = lib.mkForce [ ];
              overrideStrategy = "asDropin";
            };
            "svcvm-virtiofsd@${name}" = {
              path = lib.mkForce [ ];
              overrideStrategy = "asDropin";
            };
          }
        )
      )
      {
        "svcvm-tap-interfaces@" = {
          description = "Setup svcvm '%i' TAP interfaces";
          before = [ "svcvm@%i.service" ];
          partOf = [ "svcvm@%i.service" ];
          after = [
            "network.target"
            "svcvm-set-booted@%i.service"
          ];
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/tap-up";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            SyslogIdentifier = "svcvm-tap-interfaces@%i";
            ExecStart = "${stateDir}/%i/current/bin/tap-up";
            ExecStop = "${stateDir}/%i/booted/bin/tap-down";
          };
        };
        "svcvm-virtiofsd@" = {
          description = "VirtioFS daemons for svcvm '%i'";
          before = [ "svcvm@%i.service" ];
          partOf = [ "svcvm@%i.service" ];
          after = [
            "local-fs.target"
            "svcvm-set-booted@%i.service"
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
            SyslogIdentifier = "svcvm-virtiofsd@%i";
            Type = "notify";
            KillMode = "mixed";
          };
        };
        "svcvm-set-booted@" = {
          description = "Save svcvm '%i' booted configuration";
          before = [ "svcvm@%i.service" ];
          partOf = [ "svcvm@%i.service" ];
          restartIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            SyslogIdentifier = "svcvm-set-booted@%i";
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
        "svcvm@" = {
          description = "svcvm Service Virtual Machine '%i'";
          requires = [
            "svcvm-tap-interfaces@%i.service"
            "svcvm-virtiofsd@%i.service"
            "svcvm-set-booted@%i.service"
          ];
          after = [
            "network.target"
            "systemd-modules-load.service"
            "svcvm-tap-interfaces@%i.service"
            "svcvm-virtiofsd@%i.service"
            "svcvm-set-booted@%i.service"
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
            SyslogIdentifier = "svcvm@%i";
            LimitNOFILE = 1048576;
            NotifyAccess = "all";
            LimitMEMLOCK = "infinity";
          };
        };
      }
      (builtins.attrNames config.microvm.vms);

  systemd.targets.svcvms = {
    wantedBy = [ "multi-user.target" ];
  };

  # Enable Kernel Same-Page Merging
  hardware.ksm.enable = lib.mkDefault true;
}
