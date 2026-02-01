# OpenClaw Keycloak Configuration
# This module IMPORTS and CONFIGURES the standalone Keycloak module
# with OpenClaw-specific settings. It is a thin wrapper, not an implementation.
#
# Design:
# - Imports: ../keycloak/default.nix (standalone module)
# - Configures: OpenClaw-specific realm, clients, paths
# - Derives: Client list from cfg.instances
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw;
  keycloakCfg = cfg.zeroTrust.keycloak;
  enabledInstances = lib.filterAttrs (n: v: v.enable) cfg.instances;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

in
{
  # Import the standalone Keycloak module
  imports = [
    ../keycloak
  ];

  # OpenClaw-specific Keycloak options (thin wrapper)
  options.CUSTOM.virtualisation.openclaw.zeroTrust.keycloak = {
    enable = mkEnableOption "Keycloak identity provider for OpenClaw zero-trust secrets";

    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Keycloak admin password";
    };

    postgresPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing PostgreSQL password";
    };
  };

  # Configure the standalone module with OpenClaw-specific values
  config = mkIf (cfg.enable && cfg.zeroTrust.enable && keycloakCfg.enable) {
    CUSTOM.virtualisation.keycloak = {
      enable = true;

      # OpenClaw-specific realm
      realm = "openclaw";

      # Derive client list from enabled instances
      # Each instance gets an injector client: openclaw-injector-alpha, openclaw-injector-beta, etc.
      clients = builtins.attrNames enabledInstances;
      clientIdPrefix = "openclaw-injector";

      # OpenClaw-specific paths
      dataDir = /var/lib/openclaw/keycloak;
      clientSecretsDir = /var/lib/openclaw/keycloak/client-secrets;

      # OpenClaw-specific service naming
      servicePrefix = "openclaw-keycloak";

      # OpenClaw-specific network (shared with OpenBao)
      network = {
        name = "openclaw-secrets";
        subnet = "10.90.0.0/24";
        gateway = "10.90.0.1";
      };

      # Pass through password files
      adminPasswordFile = keycloakCfg.adminPasswordFile;
      postgres.passwordFile = keycloakCfg.postgresPasswordFile;
    };
  };
}
