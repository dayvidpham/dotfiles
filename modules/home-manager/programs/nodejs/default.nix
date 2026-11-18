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

    # npm's user config is a normal writable file; Home Manager must not own it.
    # The global prefix comes from the environment instead of being written
    # into that file, so an npm-managed (or hand-edited) .npmrc stays usable.
    home.sessionVariables = {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/.npmrc";
      NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/${npmHomePkgs}";
    };
  };
}
