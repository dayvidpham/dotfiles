{ config
, pkgs
, pkgs-unstable
, lib ? pkgs-unstable.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.nodejs;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

  npmHomePkgs = "pkgs/npm-global";
  npmConfigFile = "npm/.npmrc";
in
{
  options.CUSTOM.programs.nodejs = {
    enable = mkEnableOption "global NodeJS installation with npm prefix in user home";
    package = mkOption {
      type = lib.types.package;
      default = pkgs-unstable.nodejs;
      defaultText = lib.literalExpression "pkgs-unstable.nodejs";
      description = "NodeJS package to install as the global node/npm toolchain.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
    ];

    home.file."${npmHomePkgs}/.empty" = {
      text = "";
    };

    xdg.configFile."${npmConfigFile}" = {
      text = ''
        prefix=${config.home.homeDirectory + "/" + npmHomePkgs}
      '';
    };

    home.sessionVariables = {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome + "/" + npmConfigFile}";
    };
  };
}
