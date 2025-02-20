{ config
, pkgs
, lib ? pkgs.lib
, terminal
, menu
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
    getExe
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
        exec-once = ${getExe pkgs.swww} img $HOME/Pictures/wallpapers/david_1997-2021.jpg --resize fit --transition-type center
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
        xdg-desktop-portal-gtk
      ];
    };


    CUSTOM.services.kanshi.enable = true;

    CUSTOM.services.swww.enable = true;
    CUSTOM.services.hypridle.enable = true;
    CUSTOM.programs.hyprlock.enable = true;

    # GUI elements: widgets and status bars
    CUSTOM.theme = {
      enable = true;
      name = "balcony";
    };

    # TODO: Move notification daemon into CUSTOM.theme too
    services.mako = {
      enable = true;
      defaultTimeout = 5000;
    };




    home.packages = with pkgs; [
      run-cwd
      scythe
      polkit_gnome
    ];

    # NOTE: For multi-gpu systems
    # https://wiki.hyprland.org/Configuring/Multi-GPU/
    #xdg.configFile = (mkIf (hasAttr GLOBALS.hostName hosts) {
    #  "hypr/card-dgpu".source =
    #    mkOutOfStoreSymlink hosts."${GLOBALS.hostName}".card-dgpu;

    #  "hypr/card-igpu".source =
    #    mkOutOfStoreSymlink hosts."${GLOBALS.hostName}".card-igpu;
    #});

    home.sessionVariables = mkMerge [
      {
        XDG_CURRENT_DESKTOP = "hyprland";
        NIXOS_OZONE_WL = "1"; # Tell electron apps to use Wayland
        MOZ_ENABLE_WAYLAND = "1"; # Run Firefox on Wayland
      }

      #(mkIf (GLOBALS.hostName == "desktop") {
      #  # Fuck it: use dGPU for everything
      #  WLR_DRM_DEVICES = "${hyprHome}/card-dgpu";
      #})
      #(mkIf (GLOBALS.hostName == "flowX13") {
      #  # TODO: Must test which value is correct for laptop
      #  # Use iGPU for everything
      #  WLR_DRM_DEVICES = "${hyprHome}/card-igpu";
      #})
    ];

  };
}
