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
        windowManager = "sway";
      };

      wayland.windowManager.sway =
        let
          modifier = "Mod1";
          terminal = "${pkgs.alacritty}/bin/alacritty";
        in
        {
          enable = false;
          config = {
            terminal = terminal;
            output = {
              "eDP-1" = {
                mode = "1920x1200@119.90Hz";
                scale = "1.25";
              };

              # NOTE: 3 monitor setup: |V|[ H ]|V|
              "DP-3" = {
                # left
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "0,0";
                transform = "90";
                adaptive_sync = "on";
              };
              "DP-2" = {
                # center
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "960,300";
                adaptive_sync = "on";
              };
              "DP-1" = {
                # right
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "2666,0";
                transform = "90";
                adaptive_sync = "on";
              };

              # NOTE: 3 monitor setup: |V|[ H ]|V|
              "DP-6" = {
                # left
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "0,0";
                transform = "90";
                adaptive_sync = "on";
              };
              "DP-5" = {
                # center
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "960,300";
                adaptive_sync = "on";
              };
              "DP-4" = {
                # right
                mode = "2560x1440@169.831Hz";
                scale = "1.5";
                position = "2666,0";
                transform = "90";
                adaptive_sync = "on";
              };
            };
            bars = [
              {
                command = "${pkgs.waybar}/bin/waybar";
              }
            ];
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
        alacritty
        waybar
        polkit_gnome
        run-cwd
        scythe
      ];
    };
}
