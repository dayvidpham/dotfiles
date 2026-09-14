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
    optionalString
    ;

  remoteDesktop = pkgs.writeShellApplication {
    name = "remote-desktop";
    runtimeInputs = [ cfg.viewer pkgs.openssh pkgs.coreutils ];
    text = ''
      # Attach to the desktop's persistent remote session (wayvnc) over the
      # tailnet. Closing the viewer leaves the session running.
      host="''${1:-${cfg.host}}"
      port="''${2:-${toString cfg.port}}"

      tunnel_pid=""
      cleanup() {
        if [ -n "$tunnel_pid" ] && kill -0 "$tunnel_pid" 2>/dev/null; then
          kill "$tunnel_pid" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT INT TERM

      ${optionalString cfg.clipTunnel.enable ''
      # Forward the laptop's clipd socket to the remote host for the duration of
      # this viewer session, so the remote session can paste this machine's
      # clipboard (including images, which VNC's own text-only clipboard cannot).
      # Dedicated, non-multiplexed connection: a reused ControlMaster would not
      # add the -R. Uses key auth, so no password prompt.
      ssh -N \
        -o ControlMaster=no -o ControlPath=none \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -R ${cfg.clipTunnel.socketPath}:${cfg.clipTunnel.socketPath} \
        "$host" &
      tunnel_pid=$!
      ''}

      # Deliberately not exec'd: the trap must run once the viewer exits.
      ${cfg.viewerCommand} "$host:$port"
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

    clipTunnel = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Forward this machine's clipd socket to the remote host for the
          lifetime of the viewer session, so the remote session can paste this
          machine's clipboard. Requires the clipd user service here and the
          peer sync (clip-sync) on the remote.
        '';
      };

      socketPath = mkOption {
        type = types.str;
        default = "/run/user/1000/clipd.sock";
        description = "clipd unix socket path; the same path is used on both ends";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.viewer remoteDesktop ];
  };
}
