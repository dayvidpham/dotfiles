{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.waybar;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    mkMerge
    ;


in
{
  options.CUSTOM.programs.waybar = {
    enable = mkEnableOption
      "Customized waybar, dependant on the current window manager";
    windowManager = mkOption {
      type = lib.types.enum [ "hyprland" "sway" ];
      description = "Which Wayland window manager is enabled";
      example = "hyprland";
    };
    theme = mkOption {
      type = lib.types.enum [ "balcony" ];
      default = "balcony";
      description = "preconfigured Waybar themes";
      example = ''
        balcony
        tokyo
      '';
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.windowManager == "hyprland")
      (
        let
          waybar-themed = pkgs."waybar-${cfg.theme}";
          settings = [ waybar-themed.passthru.config ];
          style = waybar-themed.passthru.style;
        in
        {
          programs.waybar = {
            enable = true;
            systemd.enable = true;
            package = waybar-themed;
            inherit settings style;
          };

          # TODO: Place in the theme property?
          programs.rofi = {
            enable = true;
          };
        }
      ))


    # NOTE: DEPRECATED
    (mkIf (cfg.enable && cfg.windowManager == "sway") {
      programs.waybar = {
        enable = true;
        settings = [{
          height = 30;
          layer = "bottom";
          position = "top";
          tray = { spacing = 10; };
          modules-center = [ "sway/window" ];
          modules-left = [ "sway/workspaces" "sway/mode" ];
          modules-right = [
            "custom/pipewire"
            "network"
            "cpu"
            "memory"
            "temperature"
            "battery"
            "clock"
            "tray"
          ];
          battery = {
            format = "{capacity}% {icon}";
            format-alt = "{time} {icon}";
            format-charging = "{capacity}% ";
            format-icons = [ "" "" "" "" "" ];
            format-plugged = "{capacity}% ";
            states = {
              critical = 15;
              warning = 30;
            };
          };
          clock = {
            format-alt = "{:%Y-%m-%d}";
            tooltip-format = "{:%Y-%m-%d | %H:%M}";
          };
          cpu = {
            format = "{usage}% ";
            tooltip = false;
          };
          memory = { format = "{}% "; };
          network = {
            interval = 1;
            format-alt = "{ifname}: {ipaddr}/{cidr}";
            format-disconnected = "Disconnected ⚠";
            format-ethernet = "{ifname}: {ipaddr}/{cidr}   up: {bandwidthUpBits} down: {bandwidthDownBits}";
            format-linked = "{ifname} (No IP) ";
            format-wifi = "{essid} ({signalStrength}%) ";
          };
          "custom/pipewire" = {
            return-type = "json";
            signal = 8;
            interval = "once";
            exec = "pw-volume status";
            format = "{icon}";
            on-click = "qpwgraph";
            format-icons = {
              mute = "";
              default = [ "" "" "" "" ];
              headphones = "";
              headset = "";
            };
            # format = "{volume}% {icon} {format_source}";
            # format-bluetooth = "{volume}% {icon} {format_source}";
            # format-bluetooth-muted = " {icon} {format_source}";
            # format-icons = {
            #   car = "";
            #   # mute = "";
            #   default = [ "" "" "" "" ];
            #   # default = [ "" "" "" ];
            #   handsfree = "";
            #   headphones = "";
            #   headset = "";
            #   phone = "";
            #   portable = "";
            # };
            # format-muted = " {format_source}";
            # format-source = "{volume}% ";
            # format-source-muted = "";
          };
          "sway/mode" = { format = ''<span style="italic">{}</span>''; };
          temperature = {
            critical-threshold = 80;
            format = "{temperatureC}°C {icon}";
            format-icons = [ "" "" "" ];
          };
        }];
      };

      home.packages = with pkgs; [
        qpwgraph # patch bay stuff for pipewire
      ];
    })
  ];
}
