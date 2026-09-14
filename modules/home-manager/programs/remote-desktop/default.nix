{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.remote-desktop;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

  remoteDesktop = pkgs.writeShellApplication {
    name = "remote-desktop";
    runtimeInputs = [ cfg.viewer ];
    text = ''
      # Attach to the desktop's persistent remote session (wayvnc) over the
      # tailnet. Closing the viewer leaves the session running.
      host="''${1:-${cfg.host}}"
      port="''${2:-${toString cfg.port}}"
      exec ${cfg.viewerCommand} "$host:$port"
    '';
  };
in
{
  options.CUSTOM.programs.remote-desktop = {
    enable = mkEnableOption "remote-desktop VNC helper for the persistent session";

    host = mkOption {
      type = types.str;
      default = "desktop";
      description = "Host (tailnet name) of the remote session";
    };

    port = mkOption {
      type = types.port;
      default = 5900;
      description = "wayvnc port on the remote host";
    };

    viewer = mkOption {
      type = types.package;
      default = pkgs.tigervnc;
      description = "Package providing the VNC viewer";
      example = "pkgs.tigervnc";
    };

    viewerCommand = mkOption {
      type = types.str;
      default = "vncviewer";
      description = "Viewer binary name from `viewer` (e.g. vncviewer, gvncviewer)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.viewer remoteDesktop ];
  };
}
