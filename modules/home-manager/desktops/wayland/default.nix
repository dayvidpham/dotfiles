{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib)
    mkMerge
    ;
in
{
  imports = [
    ./hyprland
    ./sway
    ./niri
  ];

  config = {
    home.sessionVariables = mkMerge [
      {
        XDG_SESSION_TYPE = "wayland";
        #GDK_BACKEND = "wayland"; # NOTE: Might fuck with screen share?
        NIXOS_OZONE_WL = "1"; # Tell electron apps to use Wayland
        MOZ_ENABLE_WAYLAND = "1"; # Run Firefox on Wayland
        QT_QPA_PLATFORM = "wayland;xcb";
        CLUTTER_BACKEND = "wayland";
        SDL_VIDEODRIVER = "wayland,x11";
        ELECTRON_OZONE_PLATFORM_HINT = "wayland";
        BEMENU_BACKEND = "wayland";
      }
    ];
  };
}
