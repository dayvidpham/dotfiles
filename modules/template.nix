{
  config
  , pkgs
  , lib ? pkgs.lib
  , ...
}: let
  
  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
  ;

in {
  options.CUSTOM."my module path" = {
    enable = mkEnableOption "my module description";
  };

  config = let 
    cfg = config.CUSTOM."my module path";
  in mkIf cfg.enable {

  };
}
