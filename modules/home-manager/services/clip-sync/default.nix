{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.clip-sync;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    ;

  # Both clip.py and clip-sync.py must land in the same store directory,
  # because clip-sync.py imports clip.py from its own directory.
  sources = ../../../nixos/services/clipboard-tunnel/py;

  clipSync = pkgs.writeShellApplication {
    name = "clip-sync";
    runtimeInputs = [ pkgs.python3 pkgs.wl-clipboard ];
    text = ''
      exec python3 ${sources}/clip-sync.py "$@"
    '';
  };
in
{
  options.CUSTOM.services.clip-sync = {
    enable = mkEnableOption "mirror a peer clipboard into this session's clipboard (so GUI apps can paste)";

    socketPath = mkOption {
      type = types.str;
      default = "%t/clipd.sock";
      description = ''
        Peer clipd socket (%t is the user runtime dir, i.e. the destination of
        the peer's ssh RemoteForward).
      '';
    };

    interval = mkOption {
      type = types.float;
      default = 1.0;
      description = "Seconds between peer clipboard polls";
    };

    systemdTarget = mkOption {
      type = types.str;
      default = config.wayland.systemd.target;
      description = "systemd target that provides the graphical session";
      example = "config.wayland.systemd.target";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ clipSync ];

    # A user service: it inherits WAYLAND_DISPLAY/XDG_RUNTIME_DIR from the live
    # session, so it writes into whatever compositor the user actually logged
    # into (niri, sway, ...) with no socket name to guess.
    systemd.user.services.clip-sync = {
      Unit = {
        Description = "Mirror the peer clipboard into this session";
        PartOf = [ cfg.systemdTarget ];
        After = [ cfg.systemdTarget ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
        # Retry forever: the session's compositor may come up after us.
        StartLimitIntervalSec = 0;
      };

      Service = {
        ExecStart = "${getExe clipSync} ${cfg.socketPath} ${toString cfg.interval}";
        Restart = "always";
        RestartSec = 3;
      };

      Install.WantedBy = [ cfg.systemdTarget ];
    };
  };
}
