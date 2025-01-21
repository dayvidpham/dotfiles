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
    getExe
    ;

  shell =
    if config.programs.zsh.enable
    then "${config.programs.zsh.package}/bin/zsh"
    else "${pkgs.bash}/bin/bash";
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
      theme = "dark:catppuccin-frappe,light:catppuccin-latte";
      command = shell;
      font-size = 14;
    };
  };
}
