{ config
, pkgs
, lib ? pkgs.lib
, GLOBALS
, ...
}:
let
  cfg = config.CUSTOM.programs.rofi;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    mkPackageOption
    mkMerge
    literalExpression
    types
    optionalString
    ;

  inherit (builtins)
    readFile
    typeOf
    ;

in
{
  options.CUSTOM.programs.rofi = {
    enable = mkEnableOption "themed rofi-wayland config";
    package = mkPackageOption pkgs "rofi-wayland-unwrapped" { };


    configType = mkOption {
      type = types.enum [ "directory" "file" "lines" ];
      default = "directory";
      description = ''
        The type of file to be copied to xdg.configHome/rofi
      '';
      example = "directory";
    };

    config = mkOption {
      type = with types; either path lines;
      default = (GLOBALS.theme.basePath + /rofi);
      description = "Config as a string, or as a path to copy";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Lines appended to end of config";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      (mkMerge [
        (mkIf (cfg.configType == "directory") {
          assertion = (cfg.configType == "directory" && (typeOf cfg.config == "path"));
          message = ''configType is "directory" but config is a string'';
        })
        (mkIf (cfg.configType == "file") {
          assertion = (cfg.configType == "file" && (typeOf cfg.config == "path"));
          message = ''configType is "file" but config is a string'';
        })
        (mkIf (cfg.configType == "lines") {
          assertion = (cfg.configType == "lines" && (typeOf cfg.config == "lines"));
          message = ''configType is "string" but config is a path'';
        })
      ])
    ];

    home.packages = [ cfg.package ];

    xdg.configFile =
      let
        configText =
          (optionalString (cfg.configType == "directory") (readFile (cfg.config + /config.rasi)))
          + (optionalString (cfg.configType == "file") (readFile cfg.config))
          + (optionalString (cfg.configType == "lines") (cfg.config))
          + (optionalString (cfg.extraConfig != "") cfg.extraConfig);
      in
      mkMerge [
        (mkIf (cfg.configType == "directory") {
          "rofi" = {
            source = cfg.config;
          };
          "rofi/config.rasi" = {
            text = configText;
          };
        })
        (mkIf (cfg.configType == "file") {
          "rofi/config.rasi" = {
            text = configText;
          };
        })
        (mkIf (cfg.configType == "lines") {
          "rofi/config.rasi" = {
            text = configText;
          };
        })
      ];
  };
}
