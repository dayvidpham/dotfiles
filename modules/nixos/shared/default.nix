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

  shared-config = [
    system
    utils
    keyboards
  ];

in
{
  imports = [
    ./system
    ./utils
    ./keyboards
  ];

  options.CUSTOM.shared = {
    enable = mkEnableOption "shared config, tools, and utils between hosts";
  };
}
