{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.sway;

  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    ;
in
{
  options = {
    CUSTOM.programs.sway = {
      enable = mkEnableOption "sway";
    };
  };

  config = mkIf cfg.enable {
    programs.sway = {
      enable = true;
      extraOptions = [
        "--unsupported-gpu"
      ];
    };

    # To enable configuration using Home Manager
    # From https://wiki.nixos.org/wiki/Sway#Using_Home_Manager
    security.polkit.enable = true;
  };
}
