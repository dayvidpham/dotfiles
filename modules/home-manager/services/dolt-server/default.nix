# Dolt SQL Server — systemd user service
#
# Runs `dolt sql-server` as a long-lived user service. All beads databases
# are subdirectories under `dataDir`; the server exposes them all over a
# single MySQL-compatible endpoint.
#
# Default: --no-auto-commit (required for beads — MySQL COMMIT is transaction
# durability, Dolt COMMIT is version control; the beads Go code handles both).
{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.services.dolt-server;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    mkIf
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
  };

  config = mkIf cfg.enable {
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
          mkdir -p ${escapeShellArg cfg.dataDir}
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
  };
}
