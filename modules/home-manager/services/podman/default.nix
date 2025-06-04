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
  };

  config = mkIf cfg.enable {
    services.podman.enable = true;
  };
}
