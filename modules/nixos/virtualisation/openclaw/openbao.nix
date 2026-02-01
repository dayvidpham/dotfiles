# OpenClaw OpenBao Configuration
# This module IMPORTS and CONFIGURES the standalone OpenBao module
# with OpenClaw-specific settings. It is a thin wrapper, not an implementation.
#
# Design:
# - Imports: ../openbao/default.nix (standalone module)
# - Configures: OpenClaw-specific policies, OIDC roles, paths
# - Derives: Policy/role list from cfg.instances
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw;
  openbaoCfg = cfg.zeroTrust.openbao;
  keycloakCfg = cfg.zeroTrust.keycloak;
  enabledInstances = lib.filterAttrs (n: v: v.enable) cfg.instances;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  # Generate policy for each instance
  instancePolicies = builtins.map (name: {
    name = "openclaw-${name}";
    paths = [
      "secret/data/openclaw/${name}/*"
      "secret/metadata/openclaw/${name}/*"
    ];
    capabilities = [ "read" "list" ];
  }) (builtins.attrNames enabledInstances);

  # Generate OIDC role for each instance
  instanceOidcRoles = builtins.map (name: {
    name = "openclaw-injector-${name}";
    boundAudiences = [ "openclaw-injector-${name}" ];
    policies = [ "openclaw-${name}" ];
    ttl = "5m";
    maxTtl = "10m";
  }) (builtins.attrNames enabledInstances);

in
{
  # Import the standalone OpenBao module
  imports = [
    ../openbao
  ];

  # OpenClaw-specific OpenBao options (thin wrapper)
  options.CUSTOM.virtualisation.openclaw.zeroTrust.openbao = {
    enable = mkEnableOption "OpenBao secrets store for OpenClaw zero-trust secrets";

    enableUI = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OpenBao web UI (for debugging only)";
    };
  };

  # Configure the standalone module with OpenClaw-specific values
  config = mkIf (cfg.enable && cfg.zeroTrust.enable && openbaoCfg.enable) {
    # Assertions
    assertions = [
      {
        assertion = keycloakCfg.enable;
        message = "OpenClaw OpenBao requires Keycloak for OIDC authentication. Enable CUSTOM.virtualisation.openclaw.zeroTrust.keycloak";
      }
    ];

    CUSTOM.virtualisation.openbao = {
      enable = true;

      # OpenClaw-specific paths
      dataDir = /var/lib/openclaw/openbao;
      unsealKeysDir = /var/lib/openclaw/openbao/unseal-keys;
      auditLogPath = /var/log/openclaw/openbao-audit.log;

      # OpenClaw-specific service naming
      servicePrefix = "openclaw-openbao";

      # Use OIDC auth with Keycloak
      auth = {
        method = "oidc";
        oidc = {
          enable = true;
          discoveryUrl = "http://127.0.0.1:8080/realms/openclaw";
          defaultRole = "openclaw-injector";
        };
      };

      # UI setting
      enableUI = openbaoCfg.enableUI;

      # Use shared network with Keycloak (don't create new one)
      network = {
        name = "openclaw-secrets";
        createNetwork = false;  # Keycloak creates the network
      };

      # Derive policies from enabled instances
      policies = instancePolicies;

      # Derive OIDC roles from enabled instances
      oidcRoles = instanceOidcRoles;
    };
  };
}
