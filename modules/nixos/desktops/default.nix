{ ... }:

{
  imports = [
    ./sway
    ./hyprland
  ];

  config = {
    environment.sessionVariables = {
      XDG_SESSION_TYPE = "wayland";
      GDK_BACKEND = "wayland";
      NIXOS_OZONE_WL = "1"; # Tell electron apps to use Wayland
      MOZ_ENABLE_WAYLAND = "1"; # Run Firefox on Wayland
      QT_QPA_PLATFORM = "wayland;xcb";
      CLUTTER_BACKEND = "wayland";
      SDL_VIDEODRIVER = "wayland,x11";
      ELECTRON_OZONE_PLATFORM_HINT = "wayland";
      BEMENU_BACKEND = "wayland";
    };
  };
}
