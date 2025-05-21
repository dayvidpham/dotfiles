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
    {
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
      programs.niri.settings = with config.lib.niri.actions; {
        binds = lib.mergeAttrsList [
          {
            #"Super+Enter".action = spawn "${terminal}";
          }
        ];
      };
    };
}
