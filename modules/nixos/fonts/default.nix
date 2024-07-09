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

      nerdfonts-custom = pkgs.nerdfonts.override {
        fonts = [
          "DaddyTimeMono"
          "JetBrainsMono"
          "Hack"
          "Iosevka"
          "IosevkaTerm"
        ];
      };
      /* nerdfonts-custom = mkMerge [
        (mkIf (config.networking.hostName == "flowX13") (
          pkgs.nerdfonts.override {
            fonts = [
              "DaddyTimeMono"
              "JetBrainsMono"
              "Hack"
              "Iosevka"
              "IosevkaTerm"
            ];
          }))
        (mkIf (config.networking.hostName == "desktop") (
          pkgs.nerdfonts.override {
            fonts = [
              "DaddyTimeMono"
              "JetBrainsMono"
              "Hack"
              "Iosevka"
              "IosevkaTerm"
            ];
          }))
      ]; */

    in
    mkIf cfg.enable {

      fonts = {

        packages = (with pkgs; [
          noto-fonts
          noto-fonts-emoji
          font-awesome
        ]) ++ [ nerdfonts-custom ];

        enableDefaultPackages = true;

      };


      fonts.fontconfig = {

        enable = true;
        hinting.style = "medium";

      };

    };
}
