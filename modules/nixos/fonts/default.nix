{
  config
  , pkgs
  , lib ? pkgs.lib
  , ...
}: let

  inherit (lib)
    mkIf
    mkEnableOption
  ;

in {
  options.CUSTOM.fonts = {

    enable = mkEnableOption "default fonts and fontconfig";

  };

  config = let

    cfg = config.CUSTOM.fonts;

  in mkIf cfg.enable {

    fonts = {

      packages = with pkgs; [
        noto-fonts
        noto-fonts-emoji
      ];

      enableDefaultPackages = true;

    };


    fonts.fontconfig = {

      enable = true;

    };

  };
}
