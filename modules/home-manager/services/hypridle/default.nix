{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.hypridle;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    getExe
    ;

  hyprlockExe = getExe pkgs.hyprlock;

in
{
  options.CUSTOM.services.hypridle = {
    enable = mkEnableOption "hypridle to sleep and suspend system";
  };

  config = mkIf cfg.enable {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof ${hyprlockExe} || ${hyprlockExe}"; # avoid starting multiple hyprlock instances.
          before_sleep_cmd = "loginctl lock-session"; # lock before suspend.
          after_sleep_cmd = "hyprctl dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
          ignore_dbus_inhibit = false; # whether to ignore dbus-sent idle-inhibit requests (used by e.g. firefox or steam)
          ignore_systemd_inhibit = false; # whether to ignore systemd-inhibit --what=idle inhibitors

        };

        listener = [
          {
            timeout = 150; # 2.5min.
            on-timeout = "brightnessctl -s set 10"; # set monitor backlight to minimum, avoid 0 on OLED monitor.
            on-resume = "brightnessctl -r"; # monitor backlight restore.
          }

          # turn off keyboard backlight, comment out this section if you dont have a keyboard backlight.
          {
            timeout = 150; # 2.5min.
            on-timeout = "brightnessctl -s -d rgb:kbd_backlight set 0"; # turn off keyboard backlight.
            on-resume = "brightnessctl -r -d rgb:kbd_backlight"; # turn on keyboard backlight.
          }

          {
            timeout = 300; # 5min
            on-timeout = "loginctl lock-session"; # lock screen when timeout has passed
          }

          {
            timeout = 330; # 5.5min
            on-timeout = "hyprctl dispatch dpms off"; # screen off when timeout has passed
            on-resume = "hyprctl dispatch dpms on"; # screen on when activity is detected after timeout has fired.
          }

          {
            timeout = "1800"; # 30min
            on-timeout = "systemctl suspend"; # suspend pc
          }
        ];
      };
    };
  };
}
