{
  config
  , pkgs
  , lib ? pkgs.lib
  , ... 
}:
let
  cfg = config.CUSTOM.sway;

  inherit (lib) 
    mkIf
    mkEnableOption
    mkPackageOption
  ;
in {
  options = {
    CUSTOM.sway = {
      enable = mkEnableOption "sway";
    };
  };

  config = mkIf cfg.enable {

  };
}
