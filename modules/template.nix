{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.MODULE;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.MODULE = {
    enable = mkEnableOption "my module description";
  };

  config = mkIf cfg.enable { };
}
