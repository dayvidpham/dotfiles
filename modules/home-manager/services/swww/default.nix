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
    optional
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

    systemd.user.services.swww-daemon =
      let
        desktopTargets = [ "graphical-session.target" ];
        afterKanshi = desktopTargets
          ++ (optional config.services.kanshi.enable "kanshi.service");
      in
      {
        Install = { WantedBy = desktopTargets; };

        Unit = {
          ConditionEnvironment = "WAYLAND_DISPLAY";
          Description = "swww-daemon (swww wallpaper daemon)";
          After = afterKanshi;
          Requires = afterKanshi;
        };

        Service = {
          ExecStart = "${getExe' cfg.package "swww-daemon"}";
          ExecStartPost = "${getExe' cfg.package "swww"} restore";
          Restart = "always";
          RestartSec = "10";
        };
      };
  };

}

