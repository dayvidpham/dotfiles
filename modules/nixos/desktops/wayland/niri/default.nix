{ config
, pkgs
, lib ? pkgs.lib
, niri
, ...
}:
let
  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    ;

  cfg = config.CUSTOM.programs.niri;

  niri-pkg = niri.packages.${pkgs.system}.niri-stable;

  # Variables to import into the systemd user environment at session start.
  # niri --session handles WAYLAND_DISPLAY, NIRI_SOCKET, XDG_CURRENT_DESKTOP,
  # XDG_SESSION_TYPE, and DISPLAY internally; these are the login-session
  # variables that systemd user services need to inherit.
  sessionVars = [
    "PATH"
    "HOME"
    "LANG"
    "LANGUAGE"
    "SHELL"
    "XDG_RUNTIME_DIR"
    "XDG_DATA_DIRS"
    "XDG_CONFIG_DIRS"
    "DBUS_SESSION_BUS_ADDRESS"
    "SSH_AUTH_SOCK"
    "XCURSOR_THEME"
    "XCURSOR_SIZE"
    "NIXOS_OZONE_WL"
    "MOZ_ENABLE_WAYLAND"
  ];

  sessionVarsStr = builtins.concatStringsSep " " sessionVars;

  # Patch only the niri-session shell script without rebuilding the compositor.
  niri-patched = pkgs.symlinkJoin {
    name = "niri-${niri-pkg.version}";
    paths = [ niri-pkg ];
    # Pass through attributes the niri-flake module inspects on the package
    # to conditionally configure xdg portals.
    passthru = (niri-pkg.passthru or {}) // {
      inherit (niri-pkg) cargoBuildNoDefaultFeatures cargoBuildFeatures;
    };
    postBuild = ''
      rm "$out/bin/niri-session"
      cp "${niri-pkg}/bin/niri-session" "$out/bin/niri-session"
      chmod +x "$out/bin/niri-session"
      substituteInPlace "$out/bin/niri-session" \
        --replace-fail \
          'systemctl --user import-environment' \
          'systemctl --user import-environment ${sessionVarsStr}' \
        --replace-fail \
          'dbus-update-activation-environment --all' \
          'dbus-update-activation-environment --systemd ${sessionVarsStr}'
    '';
  };
in
{
  options = {
    CUSTOM.programs.niri.enable = mkEnableOption "Setup for niri env";
  };

  config = mkIf cfg.enable {
    programs.niri.enable = true;

    programs.niri.package = niri-patched;
    security.polkit.enable = true;

    CUSTOM.programs.hyprlock.enable = true;
    CUSTOM.programs.eww.enable = true;

    programs.xwayland.enable = true;
    environment.systemPackages = [
      pkgs.xwayland-satellite
    ];

    xdg.portal.enable = true;
    xdg.portal.xdgOpenUsePortal = false;
    xdg.portal.extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
    xdg.portal.configPackages = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
    xdg.portal.config = {
      niri = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "gnome" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "gnome" ];
      };
    };
  };
}
