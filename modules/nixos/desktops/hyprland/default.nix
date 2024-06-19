{
  config
  , pkgs
  , lib ? pkgs.lib
  , ... 
}:
let
  # cfg = ;
  inherit (lib) 
    mkIf
    mkEnableOption
    mkPackageOption
  ;
in {
  #options = {
  #  CUSTOM.v4l2loopback = {
  #    enable = mkEnableOption "v4l2loopback";
  #    kernelPackage = mkPackageOption config.boot.kernelPackages "v4l2loopback" {};
  #    utilsPackage = mkPackageOption pkgs "v4l-utils" {};
  #  };
  #};

  #config = mkIf cfg.enable {
  #  boot.kernelModules = [ "v4l2loopback" ];
  #  boot.extraModulePackages = [ 
  #    cfg.kernelPackage
  #  ];
  #  environment.systemPackages = [ 
  #    cfg.utilsPackage
  #  ];
  #};
}
