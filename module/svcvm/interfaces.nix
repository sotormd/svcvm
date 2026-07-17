{
  config,
  lib,
  pkgs,
  ...
}:

let
  tapInterfaces = config.svcvm.interfaces;

  tapFlags = lib.concatStringsSep " " (
    [ "vnet_hdr" ] ++ lib.optional config.svcvm.declaredRunner.passthru.tapMultiQueue "multi_queue"
  );

  # TODO: don't hardcode but obtain from host config
  user = "svcvm";
in
{
  svcvm.binScripts = lib.mkMerge [
    {
      tap-up = ''
        set -eou pipefail
      ''
      + lib.concatMapStrings ({ id, ... }: ''
        if [ -e /sys/class/net/${id} ]; then
          ${lib.getExe' pkgs.iproute2 "ip"} link delete '${id}'
        fi

        ${lib.getExe' pkgs.iproute2 "ip"} tuntap add name '${id}' mode tap user '${user}' ${tapFlags}
        ${lib.getExe' pkgs.iproute2 "ip"} link set '${id}' up
      '') tapInterfaces;

      tap-down = ''
        set -ou pipefail
      ''
      + lib.concatMapStrings ({ id, ... }: ''
        ${lib.getExe' pkgs.iproute2 "ip"} link delete '${id}'
      '') tapInterfaces;
    }
  ];
}
