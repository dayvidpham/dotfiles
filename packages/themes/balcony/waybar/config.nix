{ waybar-balcony
, scriptsDir ? "~/.local/share/waybar/scripts"
, rofi
, playerctl
, ...
}:

{
  "height" = 56; # Waybar height (to be removed for auto height)
  "layer" = "top"; # Waybar at top layer
  "modules-left" = [ "custom/launcher" "cpu" "memory" "hyprland/workspaces" "custom/weather" "custom/spotify" ];
  "modules-right" = [ "tray" "network" "backlight" "battery" "wireplumber" "clock" "custom/lock" "custom/power-menu" ];
  "hyprland/workspaces" = {
    "format" = "{icon}";
    "on-click" = "activate";
    "format-icons" = {
      "active" = " 󰮯";
      "default" = "";
    };
  };
  "hyprland/window" = {
    "format" = "{}";
  };
  "tray" = {
    "spacing" = 10;
  };
  "clock" = {
    "format" = "{:%H:%M}";
    "format-alt" = "{:%b %d %Y}";
    "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
  };

  "cpu" = {
    "interval" = 10;
    "format" = " {}%";
    "max-length" = 10;
    "on-click" = "";
  };
  "memory" = {
    "interval" = 30;
    "format" = " {}%"; #       
    "format-alt" = " {used:0.1f}GB";
    "max-length" = 10;
  };
  "backlight" = {
    "device" = "eDP-1";
    "format" = "{icon}";
    "tooltip-format" = "{percent}";
    "format-icons" = [ "󱩎 " "󱩏 " "󱩐 " "󱩑 " "󱩒 " "󱩓 " "󱩔 " "󱩕 " "󱩖 " "󰛨 " ];
  };
  "network" = {
    "format-wifi" = "{icon}";
    "format-ethernet" = ""; #  
    "format-disconnected" = "";
    "tooltip-format" = "{essid}";
    "on-click" = "bash ${scriptsDir}/network/rofi-network-manager.sh";
    "format-icons" = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
  };

  "wireplumber" = {
    "format" = "{icon}";
    "format-muted" = "";
    "format-icons" = {
      "default" = [ "" "" "" ];
    };
    "on-click" = "pavucontrol &";
  };

  "battery" = {
    "bat" = "BAT0";
    "adapter" = "ADP0";
    "interval" = 60;
    "states" = {
      "warning" = 30;
      "critical" = 15;
    };
    "max-length" = 20;
    "format" = "{icon} ";
    "format-warning" = "{icon}";
    "format-critical" = "{icon}";
    "format-charging" = "<span font-family='Font Awesome 6 Free'></span>";
    "format-plugged" = "";

    "format-alt" = "{icon} {time}";
    "format-full" = "󱊣";
    "format-icons" = [ "󱊡" "󱊢" "󱊣" ];
  };
  "custom/weather" = {
    "exec" = "${scriptsDir}/weather.py";
    "restart-interval" = 300;
    "return-type" = "json";
  };
  "custom/lock" = {
    "tooltip" = false;
    "on-click" = "swaylock";
    "format" = "";
  };
  "custom/spotify" = {
    "exec" = "${waybar-balcony}/bin/waybar-mediaplayer.py --player spotify";
    "format" = " {}";
    "return-type" = "json";
    "on-click" = "${playerctl}/bin/playerctl play-pause";
    "on-double-click-right" = "${playerctl}/bin/playerctl next";
    "on-scroll-down" = "${playerctl}/bin/playerctl previous";
  };
  "custom/power-menu" = {
    "format" = "⏻ ";
    "on-click" = "bash ${scriptsDir}/power-menu/powermenu.sh &";
  };
  "custom/launcher" = {
    "format" = "";
    "on-click" = "${rofi}/bin/rofi -show drun &";
  };
}
