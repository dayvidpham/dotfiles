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

  nodejs = pkgs-unstable.nodejs_22;
  nodePkgs = pkgs-unstable.nodePackages;
  npmHomePkgs = "pkgs/npm-global";
  npmConfigFile = "npm/.npmrc";
in
{
  options.CUSTOM.programs.nodejs = {
    enable = mkEnableOption "global NodeJS installation with npm prefix in user home";
  };

  config = mkIf cfg.enable {
    home.packages = [
      nodejs
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
