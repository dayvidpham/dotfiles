{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.moonlight;

  inherit (lib)
    mkIf
    mkOption
    mkPackageOption
    mkEnableOption
    types
    getExe
    ;

  # Thin launcher documenting the tailnet target. Moonlight-qt itself handles
  # discovery/pairing/streaming; this wrapper just pins the Sunshine host so
  # `moonlight-desktop --help` shows where to connect.
  moonlightDesktop = pkgs.writeShellApplication {
    name = "moonlight-desktop";
    runtimeInputs = [ cfg.package ];
    text = ''
      # Stream the desktop's Sunshine session over the tailnet (default ${cfg.host}).
      # Pairing: launch, add host "${cfg.host}", enter the PIN in Sunshine's web UI.
      exec ${getExe cfg.package} "$@"
    '';
  };
in
{
  options.CUSTOM.programs.moonlight = {
    enable = mkEnableOption "Moonlight-qt client for the desktop Sunshine stream";

    package = mkPackageOption pkgs "moonlight-qt" { };

    host = mkOption {
      type = types.str;
      default = "desktop";
      description = "Tailnet hostname of the Sunshine server (desktop headless sway/NVENC).";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package moonlightDesktop ];
  };
}
