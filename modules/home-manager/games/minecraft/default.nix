{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.games.minecraft;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    mkPackageOption
    ;

in
{
  options.CUSTOM.games.minecraft = {
    enable = mkEnableOption "adds Minecraft and launcher dependencies";
    package = mkPackageOption pkgs "prismlauncher" {
      default = [ "prismlauncher" ];
      example = "pkgs.prismlauncher";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
