{ config
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.btop;

  inherit (lib)
    mkIf
    mkEnableOption
    ;
in
{
  options.CUSTOM.programs.btop = {
    enable = mkEnableOption "btop system monitor config";
  };

  config = mkIf cfg.enable {
    xdg.configFile."btop/btop.conf".source =
      config.lib.file.mkOutOfStoreSymlink "/home/minttea/dotfiles/modules/home-manager/programs/btop/btop.conf";
  };
}
