{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config._internal) user group;

  inherit (config.svcvm) stateDir;
  svcvm-cli = pkgs.callPackage ./svcvm-cli.nix { inherit stateDir; };
in
{
  # create the stateDir for all svcvms
  systemd.tmpfiles.rules = [ "d ${stateDir} 755 ${user} ${group} -" ];

  # install the svcvm cli
  environment.systemPackages = [ svcvm-cli ];

  # create the user
  _internal = {
    user = "svcvm";
    group = "kvm";
  };

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
            guestConfig = config.svcvm.vms.${name}.config.config;
            runner = guestConfig._internal.runner;
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
              wantedBy = [ "svcvm.target" ];
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
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/svcvm-run";
          restartIfChanged = false;
          serviceConfig = {
            Type = "simple";
            WorkingDirectory = "${stateDir}/%i";
            ExecStart = "${stateDir}/%i/current/bin/svcvm-run";
            ExecStop = "${stateDir}/%i/booted/bin/svcvm-shutdown";
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
      (builtins.attrNames config.svcvm.vms);

  # create a svcvm target
  systemd.targets.svcvm.wantedBy = [ "multi-user.target" ];

  # Enable Kernel Same-Page Merging
  hardware.ksm.enable = lib.mkDefault true;
}
