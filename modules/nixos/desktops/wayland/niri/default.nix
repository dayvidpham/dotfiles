{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    ;

  cfg = config.CUSTOM.programs.niri;
in
{
  options = {
    cfg.enable = mkEnableOption "Setup for niri env";
  };

  config = mkIf cfg.enable {
    programs.niri.enable = true;
    security.polkit.enable = true;

    CUSTOM.programs.swaylock.enable = true;
    CUSTOM.programs.eww.enable = true;
  };
}
