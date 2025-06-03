{ config
, pkgs
, lib ? config.lib
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

    xdg.configFile."ghostty/config".source = lib.mkForce (config.lib.file.mkOutOfStoreSymlink "/home/minttea/dotfiles/modules/home-manager/programs/ghostty/config");
  };
}
