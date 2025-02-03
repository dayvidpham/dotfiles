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
    in
    mkIf cfg.enable {

      fonts = {
        packages = (with pkgs; [
          noto-fonts
          noto-fonts-emoji
          font-awesome
        ]) ++ (with pkgs.nerd-fonts; [
          daddy-time-mono
          jetbrains-mono
          hack
          iosevka
          iosevka-term
        ]);

        enableDefaultPackages = true;

        fontconfig = {
          enable = true;
          antialias = true;
          hinting.enable = true;
          hinting.style = "none";
        };
      };

    };
}
