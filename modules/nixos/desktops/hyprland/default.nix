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
in
{
  options = {
    CUSTOM.programs.hyprland.enable = mkEnableOption "Setup for hyprland env";
  };

  config =
    let
      cfg = config.CUSTOM.programs.hyprland;
    in
    mkIf cfg.enable {
      programs.hyprland.enable = true;
      CUSTOM.programs.hyprlock.enable = true;
      CUSTOM.programs.eww.enable = true;
    };
}
