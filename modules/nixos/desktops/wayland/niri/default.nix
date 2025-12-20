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

    programs.xwayland.enable = true;
    environment.systemPackages = [
      pkgs.xwayland-satellite
    ];

    xdg.portal.enable = true;
    xdg.portal.xdgOpenUsePortal = false;
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    xdg.portal.configPackages = [ pkgs.xdg-desktop-portal-gtk ];
    xdg.portal.config = {
      niri = {
        default = [
          "gtk"
        ];
        extraPortals = [
          pkgs.xdg-desktop-portal-gnome
        ];
      };
    };
  };
}
