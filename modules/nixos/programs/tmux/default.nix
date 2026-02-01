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

    # System-level tmux service running as the specified user
    # Socket created at /tmp/tmux-${UID}/default - user can attach with `tmux a`
    systemd.services.tmux-server = {
      description = "Persistent tmux server for ${cfg.server.user}";
      documentation = [ "man:tmux(1)" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "forking";
        User = cfg.server.user;
        Group = "users";

        # Start tmux server, creating a session if none exist
        ExecStart = pkgs.writeShellScript "tmux-server-start" ''
          if ${tmux} has-session 2>/dev/null; then
            echo "tmux server already running with sessions"
            exit 0
          fi
          exec ${tmux} new-session -d -s "${cfg.server.defaultSession}"
        '';

        ExecStop = "${tmux} kill-server";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
}
