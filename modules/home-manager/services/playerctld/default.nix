{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.playerctld;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.services.playerctld = {
    enable = mkEnableOption
      "playerctl daemon, auto-selects most appropriate MPRIS-enabled media player for playerctl to control";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      playerctl
    ];

    services.playerctld.enable = true;
  };
}
