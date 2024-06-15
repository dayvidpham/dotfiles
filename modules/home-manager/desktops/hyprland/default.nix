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
    mkEnableOption
  ;

in {

  options.CUSTOM.wayland.windowManager.hyprland = {

    enable = mkEnableOption "complete, personal Hyprland setup";

  };

  config = mkIf cfg.enable {

    wayland.windowManager.hyprland = {
      enable = true;
      extraConfig = ''
        ${builtins.readFile ./hyprland.conf}
      '';
    };

    home.sessionVariables = {
      XDG_CURRENT_DESKTOP         = "hyprland";
      # NOTE: Use iGPU on desktop: will need to change for laptop
      WLR_DRM_DEVICES             = "/dev/dri/card2:/dev/dri/card1";
    };

  };

}
