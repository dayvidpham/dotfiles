{ config
, pkgs
, lib ? pkgs.lib
, ...
}:

{
  config =
    let
      cfg = config.CUSTOM.theme;

    in
    lib.mkIf cfg.enable {
      home.packages = with pkgs; [
        kdePackages.breeze
        gnome-settings-daemon
        gsettings-desktop-schemas
        gsettings-qt
      ];

      qt.style.name = "breeze";
    };
}
