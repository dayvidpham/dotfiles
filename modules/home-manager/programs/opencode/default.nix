{ config
, pkgs
, pkgs-unstable
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.opencode;

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
      package = pkgs-unstable.llm-agents.opencode;
    };
    programs.bun = {
      enable = true;
      package = pkgs-unstable.bun;
    };
  };
}
