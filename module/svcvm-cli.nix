{
  lib,
  openssh,
  writeShellScriptBin,
  stateDir,
}:

let
  colors = {
    normal = "\\033[0m";
    red = "\\033[0;31m";
    green = "\\033[0;32m";
    boldRed = "\\033[1;31m";
    boldYellow = "\\033[1;33m";
    boldGreen = "\\033[1;32m";
    boldCyan = "\\033[1;36m";
  };
  colored = color: text: "${colors.${color}}${text}${colors.normal}";
in
writeShellScriptBin "svcvm" ''
    set -e

    require_name() {
      if [ -z "$NAME" ]; then
        echo "missing svcvm name"
        exit 1
      fi
    }

    PATH=${lib.makeBinPath [ openssh ]}:$PATH
    STATE_DIR=${stateDir}
    ACTION=help

    case "$1" in
      ssh)
        ACTION=ssh
        NAME="$2"
        shift 2
        ;;

      ls)
        ACTION=list
        shift
        ;;

      start)
        ACTION=start
        NAME="$2"
        shift 2
        ;;

      stop)
        ACTION=stop
        NAME="$2"
        shift 2
        ;;

      restart)
        ACTION=restart
        NAME="$2"
        shift 2
        ;;

      *)
        ACTION=help
        ;;
    esac

    DIR=$STATE_DIR/$NAME

    case $ACTION in
      help)
        echo "svcvm Service Virtual Machines for NixOS"
        echo
        cat << EOF
  Usage: $0 <command> [args]

  Commands:
          start <name>     Start svcvm@<name>.service
          stop <name>      Stop svcvm@<name>.service
          restart <name>   Restart svcvm@<name>.service
          ssh <name>       SSH into a svcvm via VSOCK
          ls               List svcvms
  EOF
        ;;

      start)
        require_name
        systemctl start "svcvm@$NAME.service"
        ;;

      stop)
        require_name
        systemctl stop "svcvm@$NAME.service"
        ;;

      restart)
        require_name
        systemctl restart "svcvm@$NAME.service"
        ;;

      list)
        for DIR in "$STATE_DIR"/* ; do
          NAME=$(basename "$DIR")
          if [ -d "$DIR" ] && [ -L "$DIR/current" ] ; then
            CURRENT_SYSTEM=$(readlink "$DIR/current/share/svcvm/system")
            CURRENT=''${CURRENT_SYSTEM#*-}

            if [ -e "$DIR/toplevel" ]; then
              # Should always equal current system
              NEW_SYSTEM=$(readlink "$DIR/toplevel")
            else
              echo -e "${colored "red" "svcvm $NAME has an inconsistent state (missing toplevel symlink)"}"
              exit 1
            fi
            NEW=''${NEW_SYSTEM#*-}

            if systemctl is-active -q "svcvm@$NAME" ; then
              echo -n -e "${colors.boldGreen}"
            elif [ -e "$DIR/booted" ]; then
              echo -n -e "${colors.boldYellow}"
            else
              echo -n -e "${colors.boldRed}"
            fi
            echo -n -e "''${NAME}${colors.normal}: "
            if [ "$CURRENT_SYSTEM" != "$NEW_SYSTEM" ] ; then
              echo -e "${colored "red" "svcvm $NAME has an inconsistent state (current != toplevel)"}"
              exit 1
            elif [ -L "$DIR/booted" ]; then
              BOOTED_SYSTEM=$(readlink "$DIR/booted/share/svcvm/system")
              BOOTED=''${BOOTED_SYSTEM#*-}
              if [ "$NEW_SYSTEM" = "$BOOTED_SYSTEM" ]; then
                echo -e "${colored "green" "current"}(${colored "green" "$BOOTED"})"
              else
                echo -e "${colored "red" "stale"}(${colored "green" "$BOOTED"}), reboot(${colored "green" "$NEW"}): ${colored "boldCyan" "svcvm restart $NAME"}"
              fi
            else
              echo -e "${colored "green" "current"}(${colored "green" "$CURRENT"}), not booted: ${colored "boldCyan" "svcvm start $NAME"}"
            fi
          fi
        done
        ;;

      ssh)
        require_name
        if [ ! -d "$DIR" ]; then
          echo -e "${colored "red" "svcvm $NAME not found"}"
          exit 1
        fi

        # Check if VM is running
        if ! systemctl is-active -q "svcvm@$NAME" ; then
          echo -e "${colored "red" "svcvm $NAME is not running"}"
          exit 1
        fi

        VSOCK_CID=""
        if [ -f "$DIR/current/share/svcvm/vsock-cid" ]; then
          VSOCK_CID=$(cat "$DIR/current/share/svcvm/vsock-cid")
        fi

        if [ -z "$VSOCK_CID" ]; then
          echo -e "${colored "red" "svcvm $NAME does not have VSOCK enabled"}"
          echo "Set microvm.vsock.cid in the VM configuration"
          exit 1
        fi

        # qemu uses native AF_VSOCK with CID
        SSH_TARGET="vsock/$VSOCK_CID"

        SSH_EXTRA_OPTS=()
        SSH_REMOTE_CMD=()
        if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
          shift
          SSH_EXTRA_OPTS=("$@")
        else
          SSH_REMOTE_CMD=("$@")
        fi

        HAS_LOGIN_OPT=false
        for opt in "''${SSH_REMOTE_CMD[@]}"; do
          case "$opt" in
            -l|--login)
              HAS_LOGIN_OPT=true
              break
            ;;
          esac
        done
        if [ "$HAS_LOGIN_OPT" = false ]; then
          SSH_REMOTE_CMD=("-l" "root" "''${SSH_REMOTE_CMD[@]}")
        fi

        echo -e "${colored "boldCyan" "Connecting to $NAME via VSOCK..."}"
        exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "''${SSH_EXTRA_OPTS[@]}" "$SSH_TARGET" "''${SSH_REMOTE_CMD[@]}"
        ;;
    esac
''
