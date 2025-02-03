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
  options.CUSTOM.programs.eww = {
    enable = mkEnableOption "Elkwars Wacky Widgets (eww) framework";
  };

  config =
    let
      cfg = config.CUSTOM.programs.eww;
    in
    mkIf cfg.enable {
      fonts.packages = with pkgs.nerd-fonts; [
        daddy-time-mono
        jetbrains-mono
        iosevka
      ];
    };
}
