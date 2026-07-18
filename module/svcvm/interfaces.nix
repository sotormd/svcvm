# networking TAP interfaces

{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config._internal) user vcpu interfaces;
in
{
  # final list of interfaces
  _internal.interfaces = config.svcvm.interfaces;

  # scripts to bring TAP interfaces up and down on host
  _internal.scripts.interfaces = lib.mkMerge [
    {
      tap-up = ''
        set -eou pipefail
      ''
      + lib.concatMapStrings ({ id, ... }: ''
        if [ -e /sys/class/net/${id} ]; then
          ${lib.getExe' pkgs.iproute2 "ip"} link delete '${id}'
        fi

        ${lib.getExe' pkgs.iproute2 "ip"} tuntap add name '${id}' mode tap user '${user}' ${
          lib.concatStringsSep " " ([ "vnet_hdr" ] ++ lib.optional (vcpu > 1) "multi_queue")
        }
        ${lib.getExe' pkgs.iproute2 "ip"} link set '${id}' up
      '') interfaces;

      tap-down = ''
        set -ou pipefail
      ''
      + lib.concatMapStrings ({ id, ... }: ''
        ${lib.getExe' pkgs.iproute2 "ip"} link delete '${id}'
      '') interfaces;
    }
  ];
}
