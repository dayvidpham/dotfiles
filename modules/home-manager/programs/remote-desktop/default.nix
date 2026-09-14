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
      trap cleanup EXIT
      # Exit (which triggers cleanup) on these too, so a closed terminal or a
      # dropped connection does not leave an orphaned ssh -R behind.
      trap 'exit 1' HUP INT TERM

      ${optionalString cfg.clipTunnel.enable ''
      # Forward the laptop's clipd socket to the remote host for the duration of
      # this viewer session, so the remote session can paste this machine's
      # clipboard (including images, which VNC's own text-only clipboard cannot).
      # Use a persistent multiplexed connection so the key passphrase is entered
      # at most once and reused by later launches; the forward rides the master.
      ssh -N \
        -o ControlMaster=auto -o ControlPath="$HOME/.ssh/clip-%h" -o ControlPersist=yes \
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

    # The clipboard travels through the ssh tunnel (clipd + clip-sync, which is
    # now bidirectional), so the VNC viewer's own clipboard is disabled to keep
    # a single authority and avoid last-writer races. This also drops the
    # primary-selection cross-wiring.
    xdg.configFile."tigervnc/default.tigervnc".text = ''
      TigerVNC Configuration file Version 1.0
      AcceptClipboard=0
      SetPrimary=0
      SendClipboard=0
      SendPrimary=0
    '';
  };
}
