# derived from https://github.com/microvm-nix/microvm
# https://github.com/microvm-nix/microvm.nix/blob/6dab06c1886c80b5bc28276e4879e699c86b3e5e/pkgs/microvm-command.nix
# modified for svcvm

{
  lib,
  openssh,
  writeShellScriptBin,
  stateDir ? "/var/lib/microvms",
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
writeShellScriptBin "microvm" ''
  set -e

  PATH=${lib.makeBinPath [ openssh ]}:$PATH
  STATE_DIR=${stateDir}
  ACTION=help

  OPTERR=1
  while getopts ":s:l" arg; do
    case $arg in
      s)
        ACTION=ssh
        NAME=$OPTARG
        ;;

      l)
        ACTION=list
        ;;

      ?)
        ACTION=help
        ;;
    esac
  done
  # consume all $@ that were processed by getopts
  shift $((OPTIND -1))
  DIR=$STATE_DIR/$NAME

  case $ACTION in
    help)
      echo microvm
      echo
      cat << EOF
  Usage: $0 [-l | -s <name>]

  Options:
          -s <name>   SSH into a microvm via VSOCK
          -l          List microvms
  EOF
      ;;
    list)
      for DIR in "$STATE_DIR"/* ; do
        NAME=$(basename "$DIR")
        if [ -d "$DIR" ] && [ -L "$DIR/current" ] ; then
          CURRENT_SYSTEM=$(readlink "$DIR/current/share/microvm/system")
          CURRENT=''${CURRENT_SYSTEM#*-}

          if [ -e "$DIR/toplevel" ]; then
            # Should always equal current system
            NEW_SYSTEM=$(readlink "$DIR/toplevel")
          else
            echo -e "${colored "red" "microvm $NAME has an inconsistent state (missing toplevel symlink)"}"
            exit 1
          fi
          NEW=''${NEW_SYSTEM#*-}

          if systemctl is-active -q "microvm@$NAME" ; then
            echo -n -e "${colors.boldGreen}"
          elif [ -e "$DIR/booted" ]; then
            echo -n -e "${colors.boldYellow}"
          else
            echo -n -e "${colors.boldRed}"
          fi
          echo -n -e "''${NAME}${colors.normal}: "
          if [ "$CURRENT_SYSTEM" != "$NEW_SYSTEM" ] ; then
            echo -e "${colored "red" "microvm $NAME has an inconsistent state (current != toplevel)"}"
            exit 1
          elif [ -L "$DIR/booted" ]; then
            BOOTED_SYSTEM=$(readlink "$DIR/booted/share/microvm/system")
            BOOTED=''${BOOTED_SYSTEM#*-}
            if [ "$NEW_SYSTEM" = "$BOOTED_SYSTEM" ]; then
              echo -e "${colored "green" "current"}(${colored "green" "$BOOTED"})"
            else
              echo -e "${colored "red" "stale"}(${colored "green" "$BOOTED"}), reboot(${colored "green" "$NEW"}): ${colored "boldCyan" "systemctl restart microvm@$NAME.service"}"
            fi
          else
            echo -e "${colored "green" "current"}(${colored "green" "$CURRENT"}), not booted: ${colored "boldCyan" "systemctl start microvm@$NAME.service"}"
          fi
        fi
      done
      ;;

    ssh)
      if [ ! -d "$DIR" ]; then
        echo -e "${colored "red" "microvm $NAME not found"}"
        exit 1
      fi

      # Check if VM is running
      if ! systemctl is-active -q "microvm@$NAME" ; then
        echo -e "${colored "red" "microvm $NAME is not running"}"
        exit 1
      fi

      VSOCK_CID=""
      if [ -f "$DIR/current/share/microvm/vsock-cid" ]; then
        VSOCK_CID=$(cat "$DIR/current/share/microvm/vsock-cid")
      fi

      if [ -z "$VSOCK_CID" ]; then
        echo -e "${colored "red" "microvm $NAME does not have VSOCK enabled"}"
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
