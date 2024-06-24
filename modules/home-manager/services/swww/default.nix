{ config
, pkgs
, lib ? pkgs.lib
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
    ;

in
{
  options.CUSTOM.services.swww = {
    enable = mkEnableOption ''
      Enable swww Wayland wallpaper daemon, use systemd by default
    '';
    package = mkPackageOption pkgs "swww" {
      default = "swww";
      #defaultText = "pkgs.swww";
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
      Install = { WantedBy = [ "graphical-session.target" ]; };

      Unit = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
        Description = "swww-daemon";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
        #X-Restart-Triggers =
        #  [ "${config.xdg.configFile."hypr/hypridle.conf".source}" ];
      };

      Service = {
        ExecStart = "${getExe' cfg.package "swww-daemon"}";
        Restart = " always ";
        RestartSec = " 10 ";
      };
    };
  };

}

