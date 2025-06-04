{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.podman;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.services.podman = {
    enable = mkEnableOption "custom userspace podman config";
    restartSystemd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "enables systemd 'podman-restart.service'";
      example = "true";
    };
  };

  config = mkIf cfg.enable {
    services.podman.enable = true;
    systemd.user.services."podman-restart" = (mkIf cfg.restartSystemd {
      wantedBy = [ "multi-user.target" ];
    });
  };
}
