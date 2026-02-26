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
    virtualisation.podman.dockerSocket.enable = true;
    virtualisation.podman.extraPackages = [
      pkgs.su
      pkgs.podman-compose
    ];
    environment.systemPackages = [
      pkgs.podman-compose
    ];

    virtualisation.docker.enable = false; # conflicts with podmanSocket

    systemd.services.podman-restart.enable = true;
    systemd.services.podman-restart.wantedBy = [ "multi-user.target" ];
    systemd.user.services.podman-restart.wantedBy = [ "multi-user.target" ];

    hardware.nvidia-container-toolkit = mkIf (config.CUSTOM.hardware.nvidia.enable && config.CUSTOM.hardware.nvidia.proprietaryDrivers.enable) {
      enable = true;
    };
  };
}
