{ config
, pkgs
, lib ? pkgs.lib
, terminal
, menu
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
  };

  config = {
    programs.niri.enable = true;

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
    programs.niri.setting = with config.lib.niri.actions; {
      binds = mergeAttrsList [
        {
          "Mod+Enter".action = spawn "${terminal}";
        }
      ];
    };
  };
}
