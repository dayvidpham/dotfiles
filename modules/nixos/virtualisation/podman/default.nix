{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.podman;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.virtualisation.podman = {
    enable = mkEnableOption "custom system-level podman config";
  };

  config = mkIf cfg.enable {
    virtualisation.podman.enable = true;
    virtualisation.podman.dockerCompat = true;
    hardware.nvidia-container-toolkit = mkIf (config.CUSTOM.hardware.nvidia.enable && config.CUSTOM.hardware.nvidia.proprietaryDrivers.enable) {
      enable = true;
    };
  };
}
