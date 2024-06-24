{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let

  cfg = config.CUSTOM.programs.hyprlock;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.programs.hyprlock = {
    enable = mkEnableOption ''
      Program to lock the screen, integrated with Hyprland.
      Requires `security.pam.services.hyprland` to exist on osConfig.
    '';
  };

  config = mkIf cfg.enable {

    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = false;
          grace = 180;
          hide_cursor = false;
          pam_module = "hyprlock";
        };

        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
          }
        ];

        input-field = [
          {
            size = "200, 50";
            position = "0, -80";
            monitor = "";
            dots_center = true;
            fade_on_empty = false;
            font_color = "rgb(202, 211, 245)";
            inner_color = "rgb(91, 96, 120)";
            outer_color = "rgb(24, 25, 38)";
            outline_thickness = 5;
            placeholder_text = ''<span foreground="##cad3f5">Password...</span>'';
            shadow_passes = 2;
          }
        ];
      };
    };
  };
}
