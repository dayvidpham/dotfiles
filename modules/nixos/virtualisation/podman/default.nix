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
    ];
    virtualisation.podman.defaultNetwork.settings = {
      dns_enabled = true;
      ipv6_enabled = true;
      network_interace = "podman0";
      subnets = [
        {
          gateway = "10.88.0.1";
          subnet = "10.88.0.0/16";
        }
        {
          gateway = "fd00:0bed:bead:food::1";
          subnet = "fd00:0bed:bead:food::/64";
        }
      ];
    };
    networking.nat.enable = true;
    networking.nat.enableIPv6 = true;
    networking.nat.internalInterfaces = [ "podman0" ];
    networking.nat.externalInterface = "tailscale0";

    virtualisation.docker.enable = false; # conflicts with podmanSocket

    systemd.services.podman-restart.enable = true;
    systemd.services.podman-restart.wantedBy = [ "multi-user.target" ];
    systemd.user.services.podman-restart.wantedBy = [ "multi-user.target" ];

    hardware.nvidia-container-toolkit = mkIf (config.CUSTOM.hardware.nvidia.enable && config.CUSTOM.hardware.nvidia.proprietaryDrivers.enable) {
      enable = true;
    };
  };
}
