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
    CUSTOM.programs.niri.enable = mkEnableOption "Setup for niri env";
  };

  config =
    let
      cfg = config.CUSTOM.programs.niri;
    in
    mkIf cfg.enable {
      programs.niri.enable = true;
      security.polkit.enable = true;

      CUSTOM.programs.swaylock.enable = true;
      CUSTOM.programs.eww.enable = true;
    };
}
