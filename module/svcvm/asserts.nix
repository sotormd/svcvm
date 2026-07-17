{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.networking) hostName;
  inherit (pkgs.stdenv.hostPlatform) system;
in
{
  assertions =
    # check for duplicate interface ids
    map (interfaces: {
      assertion = builtins.length interfaces == 1;
      message = ''
        svcvm Service Virtual Machine ${hostName}: interface id "${(builtins.head interfaces).id}" is used ${toString (builtins.length interfaces)} > 1 times.
      '';
    }) (builtins.attrValues (builtins.groupBy ({ id, ... }: id) config.svcvm.interfaces))
    ++
      # check for interface name length
      map ({ id, ... }: {
        assertion = builtins.stringLength id <= 15;
        message = ''
          svcvm Service Virtual Machine ${hostName}: interface name ${id} is longer than the
          the maximum length of 15 characters on Linux.
        '';
      }) config.svcvm.interfaces
    ++
      # check for duplicate share tags
      map (shares: {
        assertion = builtins.length shares == 1;
        message = ''
          svcvm Service Virtual Machine ${hostName}: share tag "${(builtins.head shares).tag}" is used ${toString (builtins.length shares)} > 1 times.
        '';
      }) (builtins.attrValues (builtins.groupBy ({ tag, ... }: tag) config.svcvm.shares))
    ++ [
      # ensure nix is disabled
      {
        assertion = !config.nix.enable;
        message = ''
          svcvm Service Virtual Machine ${hostName}: nix cannot be enabled within svcvms.
        '';
      }
      # ensure appropriate system
      {
        assertion = system == "x86_64-linux";
        message = ''
          svcvm Service Virtual Machine ${hostName}: svcvm only supports x86_64-linux, got ${system} instead.
        '';
      }
    ];

  warnings =
    # 32 MB is just an optimistic guess, not based on experience
    lib.optional (config.svcvm.mem < 32) ''
      svcvm Service Virtual Machine ${hostName}: ${toString config.svcvm.mem} MB of RAM is uncomfortably narrow.
    ''
    ++ lib.optional config.nix.optimise.automatic ''
      Optimising the nix store is not recommended as it either uses lots of file handles with virtiofsd or as it doesn't do what you expect with a block device.
    '';
}
