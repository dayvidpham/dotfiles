{ config
, pkgs
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.claude-code;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;
in
{
  options.CUSTOM.programs.claude-code = {
    enable = mkEnableOption "claude-code CLI AI assistant";
  };

  config = mkIf cfg.enable {
    programs.claude-code = {
      enable = true;
    };
  };
}
