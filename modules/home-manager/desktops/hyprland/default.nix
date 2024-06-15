{
  config
  , pkgs
  , lib ? pkgs.lib
  , terminal
  , menu
  , ...
}: let
  cfg = config.CUSTOM.wayland.windowManager.hyprland;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkMerge
    types
  ;

in {

  options.CUSTOM.wayland.windowManager.hyprland = {

    enable = mkEnableOption "complete, personal Hyprland setup";

    sessionVariables.WLR_DRM_DEVICES = mkOption {
      type = types.str;
      description = ''
        An environment variable that tells wlroots where the DRM devices are. This is necessary if on a multi-GPU system.

        Colon-separated list of Direct Rendering Manager (DRM) devices that the Wayland compositor will use for rendering (GPUs).

        These can be found in /dev/dri/, which contain the Direct Rendering Infrastructure (DRI) devices that provide hardware acceleration for the Mesa implementation of OpenGL.
      '';
      example = ''
        "/dev/dri/card2:/dev/dri/card1"
        "/dev/dri/card0"
      '';
    };

  };

  config = mkIf cfg.enable {

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = ''
        ${builtins.readFile ./hyprland.conf}
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

    home.sessionVariables = mkMerge [
      {
        XDG_CURRENT_DESKTOP = "hyprland";
        GDK_BACKEND         = "wayland";
        NIXOS_OZONE_WL      = "1";        # Tell electron apps to use Wayland
        MOZ_ENABLE_WAYLAND  = "1";        # Run Firefox on Wayland
      }
      cfg.sessionVariables
    ];

  };

}
