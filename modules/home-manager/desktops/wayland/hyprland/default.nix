{ config
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

    home.sessionVariables = mkMerge [
      {
        XDG_CURRENT_DESKTOP = "hyprland";
      }

      (mkIf (GLOBALS.hostName == "desktop") {
        # Fuck it: use dGPU for everything
        WLR_DRM_DEVICES = "/dev/dri/card1";
      })
      (mkIf (GLOBALS.hostName == "flowX13") {
        # TODO: Must test which value is correct for laptop
        # Use iGPU for everything
        WLR_DRM_DEVICES = "/dev/dri/card0";
      })
      /*
      description = ''
        An environment variable that tells wlroots where the DRM devices are. This is necessary if on a multi-GPU system.

        Colon-separated list of Direct Rendering Manager (DRM) devices that the Wayland compositor will use for rendering (GPUs).

        These can be found in /dev/dri/, which contain the Direct Rendering Infrastructure (DRI) devices that provide hardware acceleration for the Mesa implementation of OpenGL.
      '';
      example = ''
        "/dev/dri/card2:/dev/dri/card1"
        "/dev/dri/card0"
      '';
      */
    ];

  };
}
