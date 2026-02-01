# Standalone Keycloak Identity Provider Module
# Deploys Keycloak in a Podman container for OIDC-based authentication
# This module is GENERIC and can be used by any service, not just OpenClaw
#
# Design principles:
# - No hardcoded application-specific names (realm, paths, service names)
# - All configuration is parameterized via options
# - Can deploy multiple independent Keycloak instances
# - Supports explicit client list (no dependency on parent module structure)
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.keycloak;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    optionalString
    concatStringsSep
    ;

  # Generate realm configuration from options
  realmConfig = pkgs.writeText "${cfg.realm}-realm.json" (builtins.toJSON {
    realm = cfg.realm;
    enabled = true;
    sslRequired = if cfg.sslRequired then "external" else "none";
    registrationAllowed = false;
    loginWithEmailAllowed = false;
    duplicateEmailsAllowed = false;
    resetPasswordAllowed = false;
    editUsernameAllowed = false;
    bruteForceProtected = true;

    # Service accounts for clients
    clients = builtins.map (clientName: {
      clientId = "${cfg.clientIdPrefix}-${clientName}";
      enabled = true;
      clientAuthenticatorType = "client-secret";
      serviceAccountsEnabled = true;
      standardFlowEnabled = false;
      directAccessGrantsEnabled = false;
      publicClient = false;
      protocol = "openid-connect";
      attributes = {
        "access.token.lifespan" = toString cfg.tokenLifespan;
      };
      defaultClientScopes = [ "openid" "profile" ];
    }) cfg.clients;
  });

  # Container images
  postgresImage = "docker.io/library/postgres:16-alpine";
  keycloakImage = "quay.io/keycloak/keycloak:26.0";

  # Service name prefix for all systemd services
  svcPrefix = cfg.servicePrefix;

in
{
  options.CUSTOM.virtualisation.keycloak = {
    enable = mkEnableOption "Keycloak identity provider";

    # Realm configuration
    realm = mkOption {
      type = types.str;
      default = "keycloak";
      description = "Name of the Keycloak realm to create";
      example = "myapp";
    };

    clients = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of client names to create service accounts for";
      example = [ "api" "worker" "injector" ];
    };

    clientIdPrefix = mkOption {
      type = types.str;
      default = "client";
      description = "Prefix for client IDs (clientId = prefix-name)";
      example = "myapp-service";
    };

    tokenLifespan = mkOption {
      type = types.int;
      default = 300;
      description = "Access token lifespan in seconds";
    };

    sslRequired = mkOption {
      type = types.bool;
      default = false;
      description = "Require SSL for external connections";
    };

    # Server configuration
    hostname = mkOption {
      type = types.str;
      default = "keycloak.internal";
      description = "Internal hostname for Keycloak";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8080;
      description = "HTTP port for Keycloak (internal only)";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Keycloak admin username";
    };

    adminPasswordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to file containing Keycloak admin password";
    };

    # Storage configuration
    dataDir = mkOption {
      type = types.path;
      default = /var/lib/keycloak;
      description = "Directory for Keycloak and PostgreSQL data";
    };

    # Service naming
    servicePrefix = mkOption {
      type = types.str;
      default = "keycloak";
      description = "Prefix for systemd service names";
      example = "myapp-keycloak";
    };

    # PostgreSQL configuration
    postgres = {
      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL port (internal only)";
      };

      database = mkOption {
        type = types.str;
        default = "keycloak";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "keycloak";
        description = "PostgreSQL user";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing PostgreSQL password";
      };
    };

    # Network configuration
    network = {
      name = mkOption {
        type = types.str;
        default = "keycloak";
        description = "Podman network name for Keycloak infrastructure";
      };

      subnet = mkOption {
        type = types.str;
        default = "10.90.0.0/24";
        description = "Subnet for Keycloak network";
      };

      gateway = mkOption {
        type = types.str;
        default = "10.90.0.1";
        description = "Gateway for Keycloak network";
      };
    };

    # Client secrets output directory
    clientSecretsDir = mkOption {
      type = types.path;
      default = /var/lib/keycloak/client-secrets;
      description = "Directory to store generated client secrets";
    };
  };

  config = mkIf cfg.enable {
    # Assertions for required configuration
    assertions = [
      {
        assertion = cfg.adminPasswordFile != null;
        message = "CUSTOM.virtualisation.keycloak.adminPasswordFile must be set";
      }
      {
        assertion = cfg.postgres.passwordFile != null;
        message = "CUSTOM.virtualisation.keycloak.postgres.passwordFile must be set";
      }
    ];

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
      "d ${cfg.dataDir}/postgres 0700 70 70 -"  # UID 70 = postgres in container
      "d ${cfg.dataDir}/keycloak 0750 1000 1000 -"  # Keycloak user
      "d ${cfg.clientSecretsDir} 0700 root root -"
    ];

    # Create the Keycloak network
    systemd.services."${svcPrefix}-network" = {
      description = "Create ${cfg.realm} Keycloak Network";
      after = [ "podman.service" ];
      requires = [ "podman.service" ];
      before = [
        "podman-${svcPrefix}-postgres.service"
        "podman-${svcPrefix}.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "${svcPrefix}-network-create" ''
          ${pkgs.podman}/bin/podman network exists ${cfg.network.name} || \
          ${pkgs.podman}/bin/podman network create \
            --driver bridge \
            --subnet ${cfg.network.subnet} \
            --gateway ${cfg.network.gateway} \
            --internal \
            ${cfg.network.name}
        '';
        ExecStop = "${pkgs.podman}/bin/podman network rm -f ${cfg.network.name} || true";
      };
    };

    # PostgreSQL container for Keycloak
    systemd.services."podman-${svcPrefix}-postgres" = {
      description = "PostgreSQL for ${cfg.realm} Keycloak";
      after = [ "podman.service" "${svcPrefix}-network.service" ];
      requires = [ "podman.service" "${svcPrefix}-network.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStart = pkgs.writeShellScript "${svcPrefix}-postgres-start" ''
          set -euo pipefail

          # Read password from file
          POSTGRES_PASSWORD="$(cat ${cfg.postgres.passwordFile})"

          exec ${pkgs.podman}/bin/podman run \
            --name ${svcPrefix}-postgres \
            --replace \
            --network ${cfg.network.name} \
            --volume "${cfg.dataDir}/postgres:/var/lib/postgresql/data:rw" \
            --env "POSTGRES_DB=${cfg.postgres.database}" \
            --env "POSTGRES_USER=${cfg.postgres.user}" \
            --env "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
            --health-cmd "pg_isready -U ${cfg.postgres.user} -d ${cfg.postgres.database}" \
            --health-interval 10s \
            --health-retries 5 \
            --read-only=false \
            --cap-drop ALL \
            --cap-add CHOWN \
            --cap-add FOWNER \
            --cap-add SETGID \
            --cap-add SETUID \
            --cap-add DAC_OVERRIDE \
            --security-opt "no-new-privileges:true" \
            ${postgresImage}
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop -t 30 ${svcPrefix}-postgres";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f ${svcPrefix}-postgres || true";
      };
    };

    # Keycloak container
    systemd.services."podman-${svcPrefix}" = {
      description = "Keycloak Identity Provider (${cfg.realm})";
      after = [
        "podman.service"
        "${svcPrefix}-network.service"
        "podman-${svcPrefix}-postgres.service"
      ];
      requires = [
        "podman.service"
        "${svcPrefix}-network.service"
        "podman-${svcPrefix}-postgres.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStartPre = pkgs.writeShellScript "${svcPrefix}-wait-postgres" ''
          # Wait for PostgreSQL to be ready
          for i in $(seq 1 30); do
            if ${pkgs.podman}/bin/podman exec ${svcPrefix}-postgres pg_isready -U ${cfg.postgres.user} -d ${cfg.postgres.database} >/dev/null 2>&1; then
              echo "PostgreSQL is ready"
              exit 0
            fi
            echo "Waiting for PostgreSQL... ($i/30)"
            sleep 2
          done
          echo "PostgreSQL failed to become ready"
          exit 1
        '';

        ExecStart = pkgs.writeShellScript "${svcPrefix}-start" ''
          set -euo pipefail

          # Read passwords from files
          KEYCLOAK_ADMIN_PASSWORD="$(cat ${cfg.adminPasswordFile})"
          KC_DB_PASSWORD="$(cat ${cfg.postgres.passwordFile})"

          exec ${pkgs.podman}/bin/podman run \
            --name ${svcPrefix} \
            --replace \
            --network ${cfg.network.name} \
            --publish "127.0.0.1:${toString cfg.httpPort}:8080" \
            --volume "${realmConfig}:/opt/keycloak/data/import/${cfg.realm}-realm.json:ro" \
            --env "KEYCLOAK_ADMIN=${cfg.adminUser}" \
            --env "KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD" \
            --env "KC_DB=postgres" \
            --env "KC_DB_URL=jdbc:postgresql://${svcPrefix}-postgres:5432/${cfg.postgres.database}" \
            --env "KC_DB_USERNAME=${cfg.postgres.user}" \
            --env "KC_DB_PASSWORD=$KC_DB_PASSWORD" \
            --env "KC_HOSTNAME=${cfg.hostname}" \
            --env "KC_HOSTNAME_STRICT=false" \
            --env "KC_HTTP_ENABLED=true" \
            --env "KC_PROXY_HEADERS=xforwarded" \
            --env "KC_HEALTH_ENABLED=true" \
            --health-cmd "curl -sf http://localhost:8080/health/ready || exit 1" \
            --health-interval 30s \
            --health-retries 3 \
            --read-only=false \
            --cap-drop ALL \
            --security-opt "no-new-privileges:true" \
            ${keycloakImage} \
            start --import-realm --optimized=false
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop -t 60 ${svcPrefix}";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f ${svcPrefix} || true";
      };
    };

    # Service to initialize Keycloak realm and create client secrets
    systemd.services."${svcPrefix}-init" = {
      description = "Initialize ${cfg.realm} Keycloak Realm and Client Secrets";
      after = [ "podman-${svcPrefix}.service" ];
      requires = [ "podman-${svcPrefix}.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        ExecStart = pkgs.writeShellScript "${svcPrefix}-init" ''
          set -euo pipefail

          KEYCLOAK_URL="http://127.0.0.1:${toString cfg.httpPort}"
          KEYCLOAK_ADMIN="${cfg.adminUser}"
          KEYCLOAK_ADMIN_PASSWORD="$(cat ${cfg.adminPasswordFile})"
          REALM="${cfg.realm}"
          CLIENT_SECRETS_DIR="${cfg.clientSecretsDir}"

          # Wait for Keycloak to be ready
          echo "Waiting for Keycloak to be ready..."
          for i in $(seq 1 60); do
            if ${pkgs.curl}/bin/curl -sf "$KEYCLOAK_URL/health/ready" >/dev/null 2>&1; then
              echo "Keycloak is ready"
              break
            fi
            if [ $i -eq 60 ]; then
              echo "Keycloak failed to become ready"
              exit 1
            fi
            echo "Waiting for Keycloak... ($i/60)"
            sleep 2
          done

          # Get admin token
          echo "Getting admin token..."
          ADMIN_TOKEN=$(${pkgs.curl}/bin/curl -sf -X POST \
            "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            -d "username=$KEYCLOAK_ADMIN" \
            -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
            -d "grant_type=password" \
            -d "client_id=admin-cli" | ${pkgs.jq}/bin/jq -r '.access_token')

          if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
            echo "Failed to get admin token"
            exit 1
          fi

          # Check if realm exists, create if not
          if ! ${pkgs.curl}/bin/curl -sf \
            "$KEYCLOAK_URL/admin/realms/$REALM" \
            -H "Authorization: Bearer $ADMIN_TOKEN" >/dev/null 2>&1; then
            echo "Creating $REALM realm..."
            ${pkgs.curl}/bin/curl -sf -X POST \
              "$KEYCLOAK_URL/admin/realms" \
              -H "Authorization: Bearer $ADMIN_TOKEN" \
              -H "Content-Type: application/json" \
              -d '{"realm": "'"$REALM"'", "enabled": true, "sslRequired": "${if cfg.sslRequired then "external" else "none"}"}'
          fi

          # Create client secrets directory
          mkdir -p "$CLIENT_SECRETS_DIR"
          chmod 700 "$CLIENT_SECRETS_DIR"

          # Create service accounts for each client
          ${concatStringsSep "\n" (builtins.map (clientName: ''
            echo "Setting up client: ${clientName}"
            CLIENT_ID="${cfg.clientIdPrefix}-${clientName}"

            # Check if client exists
            CLIENT_UUID=$(${pkgs.curl}/bin/curl -sf \
              "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
              -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.[0].id // empty')

            if [ -z "$CLIENT_UUID" ]; then
              echo "Creating client $CLIENT_ID..."
              ${pkgs.curl}/bin/curl -sf -X POST \
                "$KEYCLOAK_URL/admin/realms/$REALM/clients" \
                -H "Authorization: Bearer $ADMIN_TOKEN" \
                -H "Content-Type: application/json" \
                -d '{
                  "clientId": "'"$CLIENT_ID"'",
                  "enabled": true,
                  "clientAuthenticatorType": "client-secret",
                  "serviceAccountsEnabled": true,
                  "standardFlowEnabled": false,
                  "directAccessGrantsEnabled": false,
                  "publicClient": false,
                  "protocol": "openid-connect"
                }'

              # Get the new client UUID
              CLIENT_UUID=$(${pkgs.curl}/bin/curl -sf \
                "$KEYCLOAK_URL/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.[0].id')
            fi

            # Get or regenerate client secret
            CLIENT_SECRET=$(${pkgs.curl}/bin/curl -sf \
              "$KEYCLOAK_URL/admin/realms/$REALM/clients/$CLIENT_UUID/client-secret" \
              -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.value')

            # Store client secret
            echo "$CLIENT_SECRET" > "$CLIENT_SECRETS_DIR/${clientName}.secret"
            chmod 400 "$CLIENT_SECRETS_DIR/${clientName}.secret"
            echo "Client secret stored for ${clientName}"
          '') cfg.clients)}

          echo "Keycloak initialization complete"
        '';
      };
    };
  };
}
