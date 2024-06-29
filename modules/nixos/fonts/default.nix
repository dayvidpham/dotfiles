{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let

  inherit (lib)
    mkIf
    mkEnableOption
    mkMerge
    ;

in
{
  options.CUSTOM.fonts = {

    enable = mkEnableOption "default fonts and fontconfig";

  };

  config =
    let

      cfg = config.CUSTOM.fonts;

      nerdfonts-custom = mkMerge (with pkgs; [
        (mkIf (config.networking.hostName == "flowX13") (
          nerdfonts.override {
            fonts = [
              "DaddyTimeMono"
              "JetBrainsMono"
              "Hack"
              "Iosevka"
              "IosevkaTerm"
            ];
          }))
        (mkIf (config.networking.hostName == "desktop") (
          nerdfonts.override {
            fonts = [
              "DaddyTimeMono"
              "JetBrainsMono"
              "Hack"
              "Iosevka"
              "IosevkaTerm"
            ];
          }))
      ]);

    in
    mkIf cfg.enable {

      fonts = {

        packages = with pkgs; [
          nerdfonts-custom
          noto-fonts
          noto-fonts-emoji
          font-awesome
        ];

        enableDefaultPackages = true;

      };


      fonts.fontconfig = {

        enable = true;
        hinting.style = "none";

      };

    };
}
