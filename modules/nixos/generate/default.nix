{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.generate;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.generate = mkOption {
    description = "default attrset generator";
    default = { };
    type = lib.types.attrs;
  };
}
