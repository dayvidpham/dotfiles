# Dolt SQL Server — systemd user service
#
# Runs `dolt sql-server` as a long-lived user service. All beads databases
# are subdirectories under `dataDir`; the server exposes them all over a
# single MySQL-compatible endpoint.
#
# Default: --no-auto-commit (required for beads — MySQL COMMIT is transaction
# durability, Dolt COMMIT is version control; the beads Go code handles both).
#
# beadsIntegration: When enabled, sets BEADS_DOLT_DATA_DIR and
# BEADS_DOLT_SERVER_PORT so beads auto-discovers this server instead of
# spawning its own. Also writes PID/port state files for the IsRunning
# fast path. Only takes effect when CUSTOM.programs.beads is also enabled.
{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.services.dolt-server;
  beadsCfg = config.CUSTOM.programs.beads;

  # Parent of dataDir — where beads state files (PID, port) live.
  # e.g. dataDir = ~/.beads/dolt → stateDir = ~/.beads
  stateDir = builtins.dirOf cfg.dataDir;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    types
    ;
in
{
  options.CUSTOM.services.dolt-server = {
    enable = mkEnableOption "Dolt SQL server for beads issue tracking";

    package = mkOption {
      type = types.package;
      default = pkgs.dolt;
      description = "The dolt package to use for the server binary";
    };

    dataDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.beads/dolt";
      description = ''
        Directory containing Dolt databases (server working directory).
        Each subdirectory is exposed as a separate database.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host address to bind the Dolt SQL server";
    };

    port = mkOption {
      type = types.port;
      default = 3307;
      description = "Port for the Dolt SQL server";
    };

    noAutoCommit = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Run with --no-auto-commit. Required for beads: MySQL COMMIT
        (transaction durability) is separate from Dolt COMMIT (version
        control). The beads Go code wraps writes in BEGIN/COMMIT, then
        calls DOLT_COMMIT at logical boundaries.
      '';
    };

    beadsIntegration = {
      enable = mkEnableOption ''
        beads auto-discovery integration.

        Sets BEADS_DOLT_DATA_DIR and BEADS_DOLT_SERVER_PORT so all beads
        projects discover this systemd-managed server instead of spawning
        their own. Writes PID/port state files to stateDir (parent of
        dataDir) after server start for the IsRunning fast path.

        Only takes effect when CUSTOM.programs.beads is also enabled.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Base service
    {
      systemd.user.services.dolt-server = {
        Unit = {
          Description = "Dolt SQL Server for beads";
          After = [ "default.target" ];
        };

        Service = {
          Type = "simple";
          # Leading "-" tolerates missing dir on first start (ExecStartPre creates it)
          WorkingDirectory = "-${cfg.dataDir}";
          ExecStartPre = toString (pkgs.writeShellScript "dolt-server-mkdatadir" ''
            set -euo pipefail
            ${pkgs.coreutils}/bin/mkdir -p ${escapeShellArg cfg.dataDir}
          '');
          ExecStart = concatStringsSep " " ([
            "${cfg.package}/bin/dolt" "sql-server"
            "--host" cfg.host
            "--port" (toString cfg.port)
          ] ++ lib.optionals cfg.noAutoCommit [ "--no-auto-commit" ]);
          Restart = "on-failure";
          RestartSec = 5;
        };

        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    }

    # Beads integration: env vars + PID/port state files
    (mkIf (cfg.beadsIntegration.enable && beadsCfg.enable) {
      # BEADS_DOLT_SERVER_PORT: beads' DefaultConfig() checks this first,
      # ensuring all projects connect to the systemd-managed server.
      #
      # BEADS_DOLT_AUTO_START=0: prevents beads from auto-starting its own
      # dolt server. The systemd service handles lifecycle (Restart=on-failure,
      # WantedBy=default.target). Without this, beads' EnsureRunning() →
      # Start() → forkIdleMonitor() chain spawns rogue servers that displace
      # the systemd-managed one.
      #
      # NOTE: Do NOT set BEADS_DOLT_DATA_DIR here. It overrides DatabasePath()
      # in configfile.go, causing main.go to derive beadsDir from the global
      # data dir (filepath.Dir(dbPath)) instead of the project-local .beads/.
      # This breaks per-project database resolution — all projects would read
      # ~/.beads/metadata.json and connect to the default "beads" database.
      # home.sessionVariables only reaches login shells; non-login contexts
      # (tmux panes, Claude Code hooks, subagents) miss them. Write to
      # ~/.zshenv via programs.zsh.envExtra so ALL zsh invocations get
      # the vars, preventing beads from spawning rogue dolt servers.
      programs.zsh.envExtra = ''
        export BEADS_DOLT_SERVER_PORT=${escapeShellArg (toString cfg.port)}
        export BEADS_DOLT_AUTO_START=0
      '';

      # Write PID/port state files so beads' IsRunning() detects the
      # server on the fast path (without going through reclaimPort).
      systemd.user.services.dolt-server.Service.ExecStartPost =
        toString (pkgs.writeShellScript "dolt-server-beads-state" ''
          set -euo pipefail
          state_dir=${escapeShellArg stateDir}
          ${pkgs.coreutils}/bin/mkdir -p "$state_dir"
          ${pkgs.coreutils}/bin/echo "$MAINPID" > "$state_dir/dolt-server.pid"
          ${pkgs.coreutils}/bin/echo ${escapeShellArg (toString cfg.port)} > "$state_dir/dolt-server.port"
        '');
    })
  ]);
}
