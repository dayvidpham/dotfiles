{ config
, options
, pkgs
, lib ? pkgs.lib
, GLOBALS
, ...
}:
let
  inherit (lib)
    types
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    mkMerge
    ;
in
{
  imports = [
    ./gtk
    ./qt
  ];

  options.CUSTOM.theme = {
    enable = lib.mkEnableOption "set widget aesthetics, cursor theme, fonts, GTK colours";

    name = mkOption {
      type = types.enum [ "balcony" ];
      default = "balcony";
      description = "set theme for various widgets according to which name";
    };
  };

  config =
    let
      cfg = config.CUSTOM.theme;
    in
    mkIf cfg.enable (mkMerge [
      {
        services.xsettingsd.enable = true;
      }
      (mkIf (cfg.name == "balcony") {
        CUSTOM.programs.waybar = {
          enable = true;
          windowManager = "niri";
          theme = "balcony";
        };
        # Needed for waybar spotify module
        CUSTOM.services.playerctld.enable = true;

        # NOTE: Unused
        CUSTOM.programs.eww.enable = true;

        CUSTOM.programs.rofi = {
          enable = true;
          configType = "directory";
          config = (GLOBALS.theme.basePath + /rofi);
        };
      })
    ]);
}
