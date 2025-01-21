{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.ghostty;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;
in
{
  options.CUSTOM.programs.ghostty = {
    enable = mkEnableOption "Ghostty terminal emulator config";
  };

  config = mkIf cfg.enable {
    programs.ghostty.enable = true;
    programs.ghostty.installBatSyntax = true;
    programs.ghostty.installVimSyntax = true;
    programs.ghostty.enableZshIntegration = config.programs.zsh.enable;
    programs.ghostty.enableBashIntegration = true;
    programs.ghostty.settings = {
      theme = mkDefault "catppuccin-mocha";
      command = mkDefault "${pkgs.bash}/bin/bash";
      font-size = mkDefault 14;
    };
  };
}
