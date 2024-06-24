{ config
, osConfig
, pkgs
, lib ? pkgs.lib
, terminal
, menu
, run-cwd
, scythe
, GLOBALS
, ...
}:
let
  cfg = config.CUSTOM.wayland.windowManager.hyprland;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkMerge
    types
    ;

  inherit (config.lib.file)
    mkOutOfStoreSymlink
    ;

  inherit (builtins)
    hasAttr
    ;

  hosts = {
    desktop = {
      card-igpu = "/dev/dri/by-path/pci-0000:16:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
    };
    flowX13 = {
      card-igpu = "/dev/dri/by-path/pci-0000:08:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
    };
  };

  hyprHome = "${config.xdg.configHome}/hypr";

in
{

  options.CUSTOM.wayland.windowManager.hyprland = {

    enable = mkEnableOption "complete, personal Hyprland setup";

  };

  config = mkIf cfg.enable {

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = ''
        ${builtins.readFile ./hyprland.conf}
        exec-once = ${pkgs.polkit_gnome.outPath}/libexec/polkit-gnome-authentication-agent-1
      '';
    };

    xdg.portal = {
      enable = true;
      config = {
        hyprland = {
          default = [ "hyprland" ];
        };
      };

      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
      ];
    };

    CUSTOM.services.kanshi.enable = true;
    CUSTOM.services.playerctld.enable = true;

    CUSTOM.services.swww.enable = true;
    CUSTOM.services.hypridle.enable = true;
    CUSTOM.programs.hyprlock.enable = true;

    # GUI elements: widgets and status bars
    CUSTOM.programs.eww.enable = true;
    CUSTOM.programs.waybar = {
      enable = true;
      windowManager = "hyprland";
    };

    # Notification daemon
    services.mako = {
      enable = true;
    };

    home.packages = with pkgs; [
      run-cwd
      scythe
      polkit_gnome
    ];

    # NOTE: For multi-gpu systems
    # https://wiki.hyprland.org/Configuring/Multi-GPU/
    xdg.configFile = (mkIf (hasAttr GLOBALS.hostName hosts) {
      "hypr/card-dgpu".source =
        mkOutOfStoreSymlink hosts."${GLOBALS.hostName}".card-dgpu;

      "hypr/card-igpu".source =
        mkOutOfStoreSymlink hosts."${GLOBALS.hostName}".card-igpu;
    });

    home.sessionVariables = mkMerge [
      {
        XDG_CURRENT_DESKTOP = "hyprland";
        NIXOS_OZONE_WL = "1"; # Tell electron apps to use Wayland
        MOZ_ENABLE_WAYLAND = "1"; # Run Firefox on Wayland
      }

      (mkIf (GLOBALS.hostName == "desktop") {
        # Fuck it: use dGPU for everything
        WLR_DRM_DEVICES = "${hyprHome}/card-dgpu";
      })
      (mkIf (GLOBALS.hostName == "flowX13") {
        # TODO: Must test which value is correct for laptop
        # Use iGPU for everything
        WLR_DRM_DEVICES = "${hyprHome}/card-igpu";
      })
    ];

  };
}
