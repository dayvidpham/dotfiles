{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.distrobox;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.programs.distrobox = {
    enable = mkEnableOption "distrobox config";
  };

  config = mkIf cfg.enable {
    programs.distrobox.enable = true;
    programs.distrobox.containers = {
      sfurs = {
        clone = "registry.gitlab.com/sfurs/software:latest-develop";
        entry = true;
        nvidia = true;
      };
    };
  };
}
