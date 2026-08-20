{ config
, pkgs
, lib ? config.lib
, GLOBALS
, niri
, ...
}:
let
  cfg = config.CUSTOM.wayland.windowManager.niri;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkPackageOption
    mkMerge
    types
    getExe
    ;

  inherit (config.lib.file)
    mkOutOfStoreSymlink
    ;

  inherit (builtins)
    hasAttr
    ;
in
{
  options.CUSTOM.wayland.windowManager.niri = {
    enable = mkEnableOption "complete, personal niri setup";
    terminalPackage = mkPackageOption pkgs "ghostty" { };
  };

  config =
    let
      terminal = getExe cfg.terminalPackage;
      init-xwayland-satellite = pkgs.writeShellScriptBin
        "init-xwayland-satellite"
        (builtins.readFile ./init-xwayland-satellite.sh);
    in
    mkIf cfg.enable {
      programs.niri.enable = true;
      # Build niri against niri-flake's own nixpkgs (which follows our
      # nixpkgs-stable, 26.05). The home configs use pkgs-unstable, where
      # `libdisplay-info_0_2` was removed (turned into a `throw` alias); the
      # niri-flake derivation still hard-requires it (assert version == "0.2.0"),
      # so the default `programs.niri.package` (built from the consuming
      # unstable pkgs) fails to evaluate via xdg.portal.extraPortals.
      programs.niri.package = niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-stable;
      programs.niri.config = null;
      programs.niri.settings = null;
      xdg.configFile."niri/config.kdl".source = config.lib.file.mkOutOfStoreSymlink /home/minttea/dotfiles/modules/home-manager/desktops/wayland/niri/config.kdl;

      home.packages = [
        init-xwayland-satellite
      ];

      CUSTOM.services.xwayland-satellite.enable = true;
      CUSTOM.services.swww.enable = true;
      programs.swaylock.enable = true;

      xdg.portal.enable = true;
      xdg.portal.xdgOpenUsePortal = false;
      xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome ];
      xdg.portal.configPackages = [ pkgs.xdg-desktop-portal-gtk pkgs.xdg-desktop-portal-gnome ];
      xdg.portal.config = {
        niri = {
          default = [ "gnome" "gtk" ];
          # GNOME's portal only *delegates* FileChooser to GTK over D-Bus
          # activation, which fails ("name is not activatable") on a niri
          # session. Route the file dialog straight to GTK instead.
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
        };
      };
    };
}
