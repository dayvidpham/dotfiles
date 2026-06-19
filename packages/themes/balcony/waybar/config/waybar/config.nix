{ waybar-mediaPlayer
, scriptsDir ? "~/.local/share/waybar/scripts"
, rofi
, playerctl
, hyprlock
, pavucontrol
, getExe
}:

{
  "height" = 56; # Waybar height (to be removed for auto height)
  "layer" = "top"; # Waybar at top layer
  "modules-left" = [
    "custom/launcher"
    "cpu"
    "memory"
    "hyprland/workspaces"
    "sway/workspaces"
    "sway/mode"
    "niri/workspaces"
  ];
  "modules-center" = [
    "custom/spotify"
    "sway/window"
  ];
  "modules-right" = [
    "tray"
    "network"
    "backlight"
    "battery"
    "custom/powermode"
    "wireplumber"
    "custom/weather"
    "clock"
    "custom/lock"
    "custom/power-menu"
  ];

  # NOTE: In case we run sway
  "sway/mode" = { format = ''<span style="italic">{}</span>''; };


  ########
  # Continue as normal with Hyprland

  "hyprland/workspaces" = {
    "format" = "{}";
    "on-click" = "activate";
    /* "format-icons" = {
      "active" = "󰮯";
      "default" = " ";
    }; */
  };
  "hyprland/window" = {
    "format" = "{}";
  };

  ########
  # Niri

  "niri/workspaces" = {
    "format" = "{}";
    #"on-click" = "activate";
  };

  ########

  "tray" = {
    "spacing" = 10;
  };
  "clock" = {
    "format" = "{:%H:%M}";
    "format-alt" = "{:%b %d %Y}";
    "tooltip-format" = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
  };

  "cpu" = {
    "interval" = 5;
    "format" = " {}%";
    "max-length" = 10;
    "on-click" = "";
  };
  "memory" = {
    "interval" = 5;
    "format" = " {}%"; #       
    "format-alt" = " {used:0.1f}GB";
    "max-length" = 10;
  };
  "backlight" = {
    "device" = "eDP-1";
    "format" = "{icon}";
    "tooltip-format" = "{percent}";
    "format-icons" = [ "󱩎" "󱩏" "󱩐" "󱩑" "󱩒" "󱩓" "󱩔" "󱩕" "󱩖" "󰛨" ];
  };
  "network" = {
    "format-wifi" = "{icon}";
    "format-ethernet" = ""; #  
    "format-disconnected" = "";
    "tooltip-format" = "{essid}";
    "on-click" = "${scriptsDir}/network/rofi-network-manager.sh";
    "format-icons" = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
  };

  "wireplumber" = {
    "format" = "{icon}";
    "format-muted" = "";
    "format-icons" = {
      "default" = [ "" "" " " ];
    };
    "on-click" = "${getExe pavucontrol} &";
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
    "on-click" = "${getExe hyprlock}";
    "format" = "";
  };
  "custom/spotify" =
    let
      playerctl-spotify = "${getExe playerctl} --player spotify";
    in
    {
      "exec" = "${waybar-mediaPlayer}/bin/waybar-mediaplayer.py --player spotify";
      "format" = " {}";
      "return-type" = "json";
      "on-click" = "${playerctl-spotify} play-pause";
      "on-double-click-right" = "${playerctl-spotify} next";
      "on-scroll-down" = "${playerctl-spotify} previous";
    };
  "custom/power-menu" = {
    "format" = "⏻";
    "on-click" = "${scriptsDir}/power-menu/powermenu.sh &";
  };
  # Manual power-mode override. Default state is "auto" (TLP managed);
  # left-click cycles auto -> eco -> balanced -> performance. The script
  # signals waybar (SIGRTMIN+8) after each change so the label updates instantly;
  # the 30s poll catches silent TLP transitions (AC unplugged elsewhere).
  "custom/powermode" = {
    "exec" = "powermode --json";
    "interval" = 30;
    "signal" = 8;
    "return-type" = "json";
    "format" = "{}";
    "tooltip" = true;
    "on-click" = "powermode cycle";
    "on-click-right" = "powermode auto";
  };
  "custom/launcher" = {
    "format" = "";
    "on-click" = "${getExe rofi} -show drun &";
  };
}
