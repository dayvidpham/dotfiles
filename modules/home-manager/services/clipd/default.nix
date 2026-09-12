{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.clipd;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    ;

  clipd = pkgs.writeShellApplication {
    name = "clipd";
    runtimeInputs = [ pkgs.wl-clipboard pkgs.python3 ];
    text = ''
      exec python3 ${./clipd.py} "$@"
    '';
  };
in
{
  options.CUSTOM.services.clipd = {
    enable = mkEnableOption "clipd clipboard daemon (serves the session clipboard over a unix socket)";

    socketPath = mkOption {
      type = types.str;
      default = "%t/clipd.sock";
      description = ''
        Unix socket clipd listens on. %t is systemd's runtime-directory
        specifier ($XDG_RUNTIME_DIR for a user service), expanded at start.
        This must match the destination path of the peer's ssh RemoteForward.
      '';
    };

    systemdTarget = mkOption {
      type = types.str;
      default = config.wayland.systemd.target;
      description = "systemd target that provides the graphical session (and its WAYLAND_DISPLAY)";
      example = "config.wayland.systemd.target";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ clipd ];

    # A user service, not a system one: it inherits WAYLAND_DISPLAY and
    # XDG_RUNTIME_DIR from the running session, so there is no socket name to
    # guess. It only runs while a graphical session exists — which is the only
    # time there is a clipboard to serve anyway.
    systemd.user.services.clipd = {
      Unit = {
        Description = "clipd clipboard daemon";
        Documentation = [ "man:wl-clipboard(1)" ];
        PartOf = [ cfg.systemdTarget ];
        After = [ cfg.systemdTarget ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Service = {
        ExecStart = "${getExe clipd} ${cfg.socketPath}";
        Restart = "on-failure";
        RestartSec = 2;
      };

      Install.WantedBy = [ cfg.systemdTarget ];
    };
  };
}
