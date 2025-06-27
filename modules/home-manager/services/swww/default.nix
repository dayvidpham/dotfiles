{ config
, pkgs
, lib ? pkgs.lib
, niri
, ...
}:
let
  cfg = config.CUSTOM.services.swww;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkPackageOption
    mkEnableOption
    getExe'
    getExe
    optional
    ;

  defaultTargets = [ "graphical-session.target" ];
  desktopTargets = defaultTargets ++
    # Set wallpaper only after displays are reconfigured
    (optional config.services.kanshi.enable "kanshi.service");

  swww-restore-cache = pkgs.writeShellApplication {
    name = "swww-restore-cache";
    runtimeInputs = [
      cfg.package
      pkgs.jq
    ] ++ (lib.optionals (config.wayland.windowManager.hyprland.enable) [
      pkgs.hyprland
    ])
    ++ (lib.optionals (config.programs.niri.enable) [
      pkgs.niri
    ]);

    text = ''
      case "$XDG_CURRENT_DESKTOP" in
        "niri") windowCtl="$(niri msg -j outputs | jq -rcs 'first | keys | first')"
      ;;
        "hyprland") windowCtl="$(hyprctl monitors -j | jq -r 'if length == 3 then .[1] else .[0] end | .name')"
      ;;
        "sway") windowCtl="$(swaymsg -j outputs)"
      ;;
        *) windowCtl=""
      ;;
      esac

      centerDisplay="$windowCtl"
      echo "INFO: Using swww-cache for $centerDisplay"

      centerDisplayCache="$(find "''${XDG_CACHE_HOME}/swww" -type f -regex ".*/$centerDisplay\$" -regextype posix-extended -print -quit)"
      echo "INFO: Using cached image at $centerDisplayCache"

      ${getExe cfg.package} img --resize fit -t center --transition-fps 60 "$(cat "$centerDisplayCache")"
    '';
  };
in
{
  options.CUSTOM.services.swww = {
    enable = mkEnableOption ''
      Enable swww Wayland wallpaper daemon, use systemd by default
    '';
    package = mkPackageOption pkgs "swww" {
      default = "swww";
    };
    systemd.enable = (mkEnableOption ''
      systemd unit that runs swww-daemon
    '') // { default = true; };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      swww
    ];

    systemd.user.services.swww-daemon = {
      Install = { WantedBy = desktopTargets; };

      Unit = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
        Description = "swww-daemon (swww wallpaper daemon)";
        After = desktopTargets;
        Requires = desktopTargets;
      };

      Service = {
        ExecStart = "${getExe' cfg.package "swww-daemon"}";
        ExecStartPost = "${getExe swww-restore-cache}";
        Restart = "always";
        RestartSec = "10";
      };
    };
  };

}

