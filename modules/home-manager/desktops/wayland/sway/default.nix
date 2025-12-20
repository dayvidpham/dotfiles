{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    getExe
    ;

in
{
  options.CUSTOM.wayland.windowManager.sway = {
    enable = mkEnableOption
      "Personalized config of Sway tiling Wayland window manager";
  };

  config =
    let
      cfg = config.CUSTOM.wayland.windowManager.sway;
    in
    mkIf cfg.enable {
      CUSTOM.programs.waybar = {
        enable = true;
        # WARN: Deprecated
        #windowManager = "sway";
        #windowManager = "hyprland"; # WARN: VERY HACKY
        theme = "balcony";
      };

      # Portal configuration for Sway
      xdg.portal = {
        enable = true;
        xdgOpenUsePortal = false;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
          xdg-desktop-portal-wlr
        ];
        config = {
          sway = {
            default = [ "wlr" "gtk" ];
          };
        };
      };

      wayland.windowManager.sway =
        let
          modifier = "Mod1";
          terminal = "${pkgs.ghostty}/bin/ghostty";
        in
        {
          enable = true;
          config = {
            terminal = terminal;
            bars = [ ];
            input = {
              "Logitech G Pro" = {
                accel_profile = "flat";
                pointer_accel = "0.05";
              };
              "type:touchpad" = {
                tap = "enabled";
                accel_profile = "flat";
                pointer_accel = "0.25";
                scroll_factor = "0.25";
              };
              "*" = {
                accel_profile = "flat";
                tap = "enabled";
                natural_scroll = "false";
              };
            };
            modifier = modifier;
            keybindings = pkgs.lib.mkOptionDefault {
              "${modifier}+Return" = "exec 'run-cwd ${terminal}'";
              "${modifier}+Shift+Return" = "exec 'run-cwd ${terminal} -e ranger'";
              XF86AudioRaiseVolume = "exec 'pw-volume change +2.5%; pkill -RTMIN+8 waybar'";
              XF86AudioLowerVolume = "exec 'pw-volume change -2.5%; pkill -RTMIN+8 waybar'";
              XF86AudioMute = "exec 'pw-volume mute toggle; pkill -RTMIN+8 waybar'";
              "Ctrl+Alt+Tab" = "mode remote";
            };
            modes = {
              "remote" = {
                "Ctrl+Alt+Tab" = "mode default";
              };
              "resize" =
                let
                  cfg = config.wayland.windowManager.sway;

                in
                {
                  "${cfg.config.left}" = "resize shrink width 10 px";
                  "${cfg.config.down}" = "resize grow height 10 px";
                  "${cfg.config.up}" = "resize shrink height 10 px";
                  "${cfg.config.right}" = "resize grow width 10 px";
                  "Left" = "resize shrink width 10 px";
                  "Down" = "resize grow height 10 px";
                  "Up" = "resize shrink height 10 px";
                  "Right" = "resize grow width 10 px";
                  "Escape" = "mode default";
                  "Return" = "mode default";
                };
            };
          };
          # For remote desktop
          extraConfig = ''
            exec ${pkgs.polkit_gnome.outPath}/libexec/polkit-gnome-authentication-agent-1
          '';
        };

      home.packages = with pkgs; [
        ghostty
        polkit_gnome
        run-cwd
        scythe
      ];
    };
}
