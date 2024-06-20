{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let

  inherit (lib)
    mkIf
    mkEnableOption
    ;

in
{
  options.CUSTOM.fonts = {

    enable = mkEnableOption "default fonts and fontconfig";

  };

  config =
    let

      cfg = config.CUSTOM.fonts;

    in
    mkIf cfg.enable {

      fonts = {

        packages = with pkgs; [
          (nerdfonts.override {
            fonts = [
              "DaddyTimeMono"
              "JetBrainsMono"
              "Iosevka"
              "Hack"
              "IosevkaTerm"
            ];
          })
          noto-fonts
          noto-fonts-emoji
          font-awesome
        ];

        enableDefaultPackages = true;

      };


      fonts.fontconfig = {

        enable = true;

      };

    };
}
