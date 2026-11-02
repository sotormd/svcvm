# virtiofs filesystems shared with the svcvm guest

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config._internal) name shares;

  inherit (pkgs.python3Packages) supervisor;
  supervisord = lib.getExe' supervisor "supervisord";

  supervisord-event-handler-raw = pkgs.writeText "supervisord-event-handler" ''
    import subprocess
    import sys


    def write_stdout(s):
        # only eventlistener protocol messages may be sent to stdout
        sys.stdout.write(s)
        sys.stdout.flush()


    def write_stderr(s):
        sys.stderr.write(s)
        sys.stderr.flush()


    def main():
        count = 0
        expected_count = @virtiofsdCount@

        while True:
            write_stdout('READY\n')
            line = sys.stdin.readline()

            # read event payload and print it to stderr
            headers = dict([x.split(':') for x in line.split()])
            sys.stdin.read(int(headers['len']))
            # body = dict([x.split(':') for x in data.split()])

            if headers["eventname"] == "PROCESS_STATE_RUNNING":
                count += 1
                write_stderr("Process state running...\n")

            if headers["eventname"] == "PROCESS_STATE_STOPPING":
                count -= 1
                write_stderr("Process state stopping...\n")

            if count >= expected_count:
                subprocess.run(["systemd-notify", "--ready"])

            write_stdout('RESULT 2\nOK')


    if __name__ == '__main__':
        main()
  '';
in
{
  # final list of shares
  _internal.shares = config.svcvm.shares ++ [
    {
      tag = "ro-store";
      source = "/nix/store";
      mountPoint = "/nix/.ro-store";
    }
  ];

  # scripts for virtiofsd on the host
  _internal.scripts.shares = {
    virtiofsd-run =
      let
        supervisordConfig = {
          supervisord = {
            nodaemon = true;
            user = "root";
          };

          "eventlistener:notify" = {
            # increase the event queue buffer size such that we dont drop RUNNING events while the event handler hasnt started up yet
            buffer_size = (1 + builtins.length shares) * 16;
            command = pkgs.writers.writePython3 "supervisord-event-handler" { } (
              pkgs.replaceVars supervisord-event-handler-raw {
                # 1 for the event handler process
                virtiofsdCount = 1 + builtins.length shares;
              }
            );
            events = "PROCESS_STATE";
          };
        }
        // builtins.listToAttrs (
          map (
            {
              tag,
              source,
              readOnly,
              ...
            }:
            {
              name = "program:virtiofsd-${tag}";
              value = {
                stderr_syslog = true;
                stdout_syslog = true;
                command = pkgs.writeShellScript "virtiofsd-${tag}" ''
                  if [ $(id -u) = 0 ]; then
                    OPT_RLIMIT="--rlimit-nofile 1048576"
                  else
                    OPT_RLIMIT=""
                  fi
                  exec ${lib.getExe pkgs.virtiofsd} \
                    --socket-path=${lib.escapeShellArg "${name}-virtiofs-${tag}.sock"} \
                    --socket-group=kvm \
                    --shared-dir=${lib.escapeShellArg source} \
                    $OPT_RLIMIT \
                    --thread-pool-size `nproc` \
                    --posix-acl --xattr \
                    ${lib.optionalString readOnly ''--readonly \''}
                    --cache=auto \
                    --inode-file-handles=prefer
                '';
              };
            }
          ) shares
        );

        supervisordConfigFile = pkgs.writeText "${name}-virtiofsd-supervisord.conf" (
          lib.generators.toINI { } supervisordConfig
        );

      in
      ''
        exec ${supervisord} --configuration ${supervisordConfigFile} "$@"
      '';
  };

  # filesystem mounts
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
      ) { } shares
    )
  ];

  # fix unmounting in qemu on shutdown for /nix/store
  systemd.mounts = [
    {
      what = "store";
      where = "/nix/store";
      overrideStrategy = "asDropin";
      unitConfig.DefaultDependencies = false;
    }
  ];
}
