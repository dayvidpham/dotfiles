{ config
, pkgs
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.vscode;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;
in
{
  options.CUSTOM.programs.opencode = {
    enable = mkEnableOption "opencode CLI AI assistant";
  };

  config = mkIf cfg.enable {
    programs.opencode = {
      enable = true;
    };
  };
}
