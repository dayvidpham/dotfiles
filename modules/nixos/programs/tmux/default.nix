{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.CUSTOM.programs.tmux;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    getExe
    ;

  tmux = getExe pkgs.tmux;

  # The login session's runtime dir (/run/user/<uid>). home-manager sets
  # TMUX_TMPDIR to this so every shell talks to the same tmux server; the
  # service must match it, otherwise it creates a second, invisible server
  # under /tmp. Socket path: $TMUX_TMPDIR/tmux-<uid>/<socket name>.
  #
  # users.users.<name>.uid is null when NixOS auto-assigns the uid (and
  # config.ids.uids only covers system users), so the runtime dir may only be
  # known at runtime - the start/stop scripts resolve it with `id -u`.
  uid = config.users.users.${cfg.server.user}.uid or null;
  loginRuntimeDir = if uid != null then "/run/user/${toString uid}" else null;
  userRuntimeDirUnit = if uid != null then "user-runtime-dir@${toString uid}.service" else null;
  userHome = config.users.users.${cfg.server.user}.home or "/home/${cfg.server.user}";

  # Prefix for ExecStart/ExecStop: resolve the real uid and export the
  # runtime env so tmux targets the same socket the user's shells use.
  runtimeEnv = ''
    uid=$(id -u)
    export TMUX_TMPDIR="''${TMUX_TMPDIR:-/run/user/$uid}"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
  '';
in
{
  options.CUSTOM.programs.tmux = {
    server = {
      enable = mkEnableOption "Persistent tmux server that starts at boot and survives user session changes";

      user = mkOption {
        type = types.str;
        description = "The user to run tmux server as";
        example = "minttea";
      };

      defaultSession = mkOption {
        type = types.str;
        default = "main";
        description = "Name of the default session to create if none exist";
      };
    };
  };

  config = mkIf cfg.server.enable {
    # Required for user lingering
    security.polkit.enable = true;

    # Enable lingering so user can attach to the session even after logout
    users.users.${cfg.server.user}.linger = true;

    # System-level tmux service running as the specified user.
    # Socket at $TMUX_TMPDIR/tmux-<uid>/default (the login runtime dir) so
    # user shells attach to this server with `tmux a`.
    systemd.services.tmux-server = {
      description = "Persistent tmux server for ${cfg.server.user}";
      documentation = [ "man:tmux(1)" ];

      # Never restart on nixos-rebuild switch: the service manages the same
      # server the user's shells attach to, so a switch-driven restart would
      # kill every session (continuum restores them, but avoid the surprise).
      # Apply unit changes explicitly with `systemctl restart tmux-server`.
      restartIfChanged = false;

      wantedBy = [ "multi-user.target" ];
      # /run/user/<uid> must exist before the server can create its socket
      after = [ "network.target" ] ++ lib.optional (userRuntimeDirUnit != null) userRuntimeDirUnit;
      wants = lib.optional (userRuntimeDirUnit != null) userRuntimeDirUnit;

      serviceConfig = {
        Type = "forking";
        User = cfg.server.user;
        Group = "users";

        # HOME pins the config the server loads (~/.config/tmux/tmux.conf).
        # TMUX_TMPDIR/XDG_RUNTIME_DIR are set here only when the uid is known
        # at evaluation time; otherwise the scripts below resolve them.
        Environment = [
          "HOME=${userHome}"
        ]
        ++ lib.optional (loginRuntimeDir != null) "TMUX_TMPDIR=${loginRuntimeDir}"
        ++ lib.optional (loginRuntimeDir != null) "XDG_RUNTIME_DIR=${loginRuntimeDir}";

        # Start tmux server, creating a session if none exist
        ExecStart = pkgs.writeShellScript "tmux-server-start" ''
          ${runtimeEnv}
          if ${tmux} has-session 2>/dev/null; then
            echo "tmux server already running with sessions"
            exit 0
          fi
          exec ${tmux} new-session -d -s "${cfg.server.defaultSession}"
        '';

        ExecStop = pkgs.writeShellScript "tmux-server-stop" ''
          ${runtimeEnv}
          exec ${tmux} kill-server
        '';

        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
