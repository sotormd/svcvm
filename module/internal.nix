{ lib, ... }:

with lib;
{
  options._internal = {
    user = mkOption {
      description = "svcvm user";
      type = types.str;
      readOnly = true;
    };

    group = mkOption {
      description = "svcvm group";
      type = types.str;
      readOnly = true;
    };
  };
}
