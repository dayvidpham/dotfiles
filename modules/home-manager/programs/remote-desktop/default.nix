{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.remote-desktop;
  clipboard = config.CUSTOM.services.clip-tunnel;
  inherit (lib) mkIf mkEnableOption mkOption types optionalString;
  remoteDesktop = pkgs.writeShellApplication {
    name = "remote-desktop";
    runtimeInputs = [ cfg.viewer ];
    text = ''
      # Viewer attachment only: never create, replace, or clean up SSH forwards.
      default_host=${lib.escapeShellArg cfg.host}
      host="''${1:-$default_host}"
      port="''${2:-${toString cfg.port}}"
      ${optionalString clipboard.enable ''
      if [ "$host" != ${lib.escapeShellArg clipboard.host} ]; then
        printf '%s\n' ${lib.escapeShellArg "remote-desktop: clipboard is NOT connected to the viewed host."} \
          ${lib.escapeShellArg "The independent clip-tunnel.service still shares the clipboard with ${clipboard.host}, even while viewing another host or with no viewer. To stop sharing, disable CUSTOM.services.clip-tunnel.enable and apply the configuration; to retarget, change CUSTOM.services.clip-tunnel.host and configure the peer's clip-sync."} >&2
      fi
      ''}
      exec ${cfg.viewerCommand} "$host:$port"
    '';
  };
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "CUSTOM" "programs" "remote-desktop" "clipTunnel" "enable" ] ''
      Viewer-owned tunnels were removed. Configure CUSTOM.services.clip-tunnel.enable
      explicitly instead; its clipboard sharing lasts for the graphical session,
      including while viewing another host or with all viewers closed.
    '')
    (lib.mkRemovedOptionModule [ "CUSTOM" "programs" "remote-desktop" "clipTunnel" "socketPath" ] ''
      Configure CUSTOM.services.clip-tunnel.socketPath (local clipd) and
      CUSTOM.services.clip-tunnel.remoteSocketPath (remote clip-sync) instead.
    '')
  ];
  options.CUSTOM.programs.remote-desktop = {
    enable = mkEnableOption "remote-desktop VNC helper for the persistent session";
    host = mkOption {
      type = types.str;
      default = "desktop";
      description = "Host of the remote session; overriding this does not retarget the independent clipboard tunnel.";
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
      description = "Viewer binary name from viewer (e.g. vncviewer, gvncviewer)";
    };
  };
  config = mkIf cfg.enable {
    home.packages = [ cfg.viewer remoteDesktop ];
    # clipd + clip-sync remain the sole clipboard authority, independently of
    # viewers. Native VNC clipboard stays disabled even when the tunnel is off.
    xdg.configFile."tigervnc/default.tigervnc".text = ''
      TigerVNC Configuration file Version 1.0
      AcceptClipboard=0
      SetPrimary=0
      SendClipboard=0
      SendPrimary=0
    '';
  };
}
