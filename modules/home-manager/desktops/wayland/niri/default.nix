{ config
, pkgs
, lib ? pkgs.lib
, GLOBALS
, niri
, ...
}:
let
  cfg = config.CUSTOM.wayland.windowManager.niri;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkPackageOption
    mkMerge
    types
    getExe
    ;

  inherit (config.lib.file)
    mkOutOfStoreSymlink
    ;

  inherit (builtins)
    hasAttr
    ;
in
{
  options.CUSTOM.wayland.windowManager.niri = {
    enable = mkEnableOption "complete, personal niri setup";
    terminalPackage = mkPackageOption pkgs "ghostty" { };
  };

  config =
    let
      terminal = getExe cfg.terminalPackage;
    in
    mkIf cfg.enable {
      CUSTOM.services.xwayland-satellite.enable = true;

      programs.niri.enable = true;
      programs.niri.config = null;
      programs.niri.settings = null;
      xdg.configFile."niri/config.kdl".source = config.lib.file.mkOutOfStoreSymlink /home/minttea/dotfiles/modules/home-manager/desktops/wayland/niri/config.kdl;

      /*
         * niri config settings found at:
         * https://github.com/sodiboo/niri-flake/blob/main/docs.md#programsnirisettings
         */
      # For overriding
      #{
      #  programs.niri.config = with niri.lib.kdl; [
      #      (node "output" "eDP-1" [
      #        (leaf "scale" 2.0)
      #      ])
      #  ];
      #}
      #programs.niri.settings = with config.lib.niri.actions; {
      #  binds = lib.mergeAttrsList [
      #    {
      #      "Mod+Return".action = spawn "${terminal}";
      #      "Mod+Shift+E".action = quit;
      #    }
      #  ];
      #};
    };
}
