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
    CUSTOM.programs.niri.enable = mkEnableOption "Setup for niri env";
  };

  config = mkIf cfg.enable {
    programs.niri.enable = true;
    security.polkit.enable = true;

    CUSTOM.programs.hyprlock.enable = true;
    CUSTOM.programs.eww.enable = true;
  };
}
