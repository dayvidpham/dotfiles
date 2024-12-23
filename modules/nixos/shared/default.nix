{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}@args:
let
  inherit (lib)
    mkDefault
    mkIf
    mkEnableOption
    mkMerge
    ;

  cfg = config.CUSTOM.shared;
  utils = import ./utils args;
  keyboards = import ./keyboards args;
  system = import ./system args;
in
{
  options.CUSTOM.shared = {
    enable = mkEnableOption "shared config, tools, and utils between hosts";
  };

  config =
    mkIf (cfg.enable) (
      mkMerge [
        system
        utils
        keyboards
      ]
    )
  ;
}
