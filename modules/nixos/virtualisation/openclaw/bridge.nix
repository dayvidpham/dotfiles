# OpenClaw Inter-Instance Communication Bridge
# Provides authenticated RPC for task delegation and shared context management
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw;
  bridgeCfg = cfg.bridge;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  # Reference the external JavaScript file
  bridgeScript = ./scripts/bridge.js;

in
{
  options.CUSTOM.virtualisation.openclaw.bridge = {
    enable = mkEnableOption "OpenClaw inter-instance communication bridge" // {
      default = true;
    };

    port = mkOption {
      type = types.port;
      default = 18800;
      description = "Port for the bridge RPC service (localhost only)";
    };

    rateLimit = mkOption {
      type = types.int;
      default = 60;
      description = "Maximum requests per minute per instance";
    };

    maxDelegationDepth = mkOption {
      type = types.int;
      default = 5;
      description = "Maximum depth of task delegation chain";
    };

    auditLogPath = mkOption {
      type = types.str;
      default = "/var/log/openclaw/bridge-audit.log";
      description = "Path to the bridge audit log file";
    };
  };

  config = mkIf (cfg.enable && bridgeCfg.enable) {
    # Create log directory
    systemd.tmpfiles.rules = [
      "d /var/log/openclaw 0750 root openclaw-bridge -"
      "f ${bridgeCfg.auditLogPath} 0640 root openclaw-bridge -"
    ];

    # Bridge service
    systemd.services.openclaw-bridge = {
      description = "OpenClaw Inter-Instance Communication Bridge";
      after = [
        "network.target"
        "openclaw-network-setup.service"
      ] ++ (if cfg.secrets.enable then [ "sops-nix.service" ] else [ ]);
      requires = [ "openclaw-network-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        BRIDGE_PORT = toString bridgeCfg.port;
        SHARED_CONTEXT_PATH = "/var/lib/openclaw/shared-context";
        AUDIT_LOG_PATH = bridgeCfg.auditLogPath;
        RATE_LIMIT = toString bridgeCfg.rateLimit;
        MAX_DELEGATION_DEPTH = toString bridgeCfg.maxDelegationDepth;
      };

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "5s";

        # Run as root but with restricted privileges
        # (needs access to shared secrets)
        User = "root";
        Group = "openclaw-bridge";

        # Security hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;

        # Required paths
        ReadWritePaths = [
          "/var/lib/openclaw/shared-context"
          "/var/log/openclaw"
        ];
        ReadOnlyPaths = mkIf cfg.secrets.enable [
          config.sops.secrets."openclaw/bridge-shared-secret".path
        ];

        ExecStart = "${pkgs.nodejs_22}/bin/node ${bridgeScript}";
      };

      # Create symlink for secrets if using sops
      preStart = mkIf cfg.secrets.enable ''
        mkdir -p /run/secrets
        ln -sf ${config.sops.secrets."openclaw/bridge-shared-secret".path} /run/secrets/bridge-shared-secret
      '';
    };
  };
}
