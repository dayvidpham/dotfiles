{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.v4l2loopback;

  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    ;
in
{
  options = {
    CUSTOM.v4l2loopback = {
      enable = mkEnableOption "v4l2loopback";
      kernelPackage = mkPackageOption config.boot.kernelPackages "v4l2loopback" { };
      utilsPackage = mkPackageOption pkgs "v4l-utils" { };
    };
  };

  config = mkIf cfg.enable {
    boot.kernelModules = [ "v4l2loopback" ];
    boot.extraModulePackages = [
      cfg.kernelPackage
    ];
    boot.extraModprobeConfig = ''
      options v4l2loopback exclusive_caps=1 video_nr=0 card_label="v4l2loopback device"
    '';
    environment.systemPackages = [
      cfg.utilsPackage
    ];
  };
}
