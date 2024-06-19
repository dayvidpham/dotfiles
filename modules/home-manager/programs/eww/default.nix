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
    removePrefix
  ;

in {
  options.CUSTOM.programs.eww = {
    enable = mkEnableOption "desktop widgets framework";
  };

  config = let 
    cfg = config.CUSTOM.programs.eww;
    dataHome = config.xdg.dataHome;
    homeDirectory = config.home.homeDirectory;
  in mkIf cfg.enable {
    programs.eww = {
      enable = true;
      configDir = ./config;
    };

    # Fonts
    home.file = {
      feather-font = {
        target = removePrefix "${homeDirectory}" "${dataHome}/fonts/feather";
        source = ./fonts/feather;
      };
    };
  };
}
