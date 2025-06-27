{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.tailscale;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.services.tailscale = {
    enable = mkEnableOption "tailscale setup with working defaults";
  };

  config = mkIf cfg.enable {
    services.tailscale.enable = true;
    networking.firewall = {
      checkReversePath = "loose";
      trustedInterfaces = [ "tailscale0" ];
      allowedUDPPorts = [
        config.services.tailscale.port
      ];
      allowedTCPPorts = [
        config.services.tailscale.port
      ];
    };
  };
}
