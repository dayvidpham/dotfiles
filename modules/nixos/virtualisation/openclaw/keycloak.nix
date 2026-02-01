# OpenClaw Keycloak Identity Provider Module
# Deploys Keycloak in a Podman container for OIDC-based authentication
# Used by secrets injector to authenticate before fetching secrets from OpenBao
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
    optionalString
    concatStringsSep
    ;

  # Keycloak realm configuration for OpenClaw
  # This creates service accounts for each injector instance
  realmConfig = pkgs.writeText "openclaw-realm.json" (builtins.toJSON {
    realm = "openclaw";
    enabled = true;
    sslRequired = "none"; # Internal network only
    registrationAllowed = false;
    loginWithEmailAllowed = false;
    duplicateEmailsAllowed = false;
    resetPasswordAllowed = false;
    editUsernameAllowed = false;
    bruteForceProtected = true;

    # Service accounts for secrets injectors
    clients = builtins.map (name: {
      clientId = "openclaw-injector-${name}";
      enabled = true;
      clientAuthenticatorType = "client-secret";
      serviceAccountsEnabled = true;
      standardFlowEnabled = false;
      directAccessGrantsEnabled = false;
      publicClient = false;
      protocol = "openid-connect";
      attributes = {
        "access.token.lifespan" = "300"; # 5 minutes
      };
      # Default roles for the service account
      defaultClientScopes = [ "openid" "profile" ];
    }) (builtins.attrNames enabledInstances);

    # OpenBao OIDC client for token validation
    # This allows OpenBao to verify tokens issued by Keycloak
  });

  # PostgreSQL container for Keycloak persistence
  postgresImage = "docker.io/library/postgres:16-alpine";
  keycloakImage = "quay.io/keycloak/keycloak:26.0";

in
{
  options.CUSTOM.virtualisation.openclaw.zeroTrust.keycloak = {
    enable = mkEnableOption "Keycloak identity provider for zero-trust secrets";

    hostname = mkOption {
      type = types.str;
      default = "keycloak.openclaw.internal";
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

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw/keycloak";
      description = "Directory for Keycloak and PostgreSQL data";
    };

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

    network = {
      name = mkOption {
        type = types.str;
        default = "openclaw-secrets";
        description = "Podman network for secrets infrastructure (Keycloak + OpenBao)";
      };

      subnet = mkOption {
        type = types.str;
        default = "10.90.0.0/24";
        description = "Subnet for secrets infrastructure network";
      };

      gateway = mkOption {
        type = types.str;
        default = "10.90.0.1";
        description = "Gateway for secrets infrastructure network";
      };
    };
  };

  config = mkIf (cfg.enable && cfg.zeroTrust.enable && keycloakCfg.enable) {
    # Assertions for required configuration
    assertions = [
      {
        assertion = keycloakCfg.adminPasswordFile != null;
        message = "CUSTOM.virtualisation.openclaw.zeroTrust.keycloak.adminPasswordFile must be set";
      }
      {
        assertion = keycloakCfg.postgres.passwordFile != null;
        message = "CUSTOM.virtualisation.openclaw.zeroTrust.keycloak.postgres.passwordFile must be set";
      }
    ];

    # Create data directories
    systemd.tmpfiles.rules = [
      "d ${keycloakCfg.dataDir} 0750 root root -"
      "d ${keycloakCfg.dataDir}/postgres 0700 70 70 -"  # UID 70 = postgres in container
      "d ${keycloakCfg.dataDir}/keycloak 0750 1000 1000 -"  # Keycloak user
    ];

    # Create the secrets infrastructure network
    systemd.services.openclaw-secrets-network = {
      description = "Create OpenClaw Secrets Infrastructure Network";
      after = [ "podman.service" ];
      requires = [ "podman.service" ];
      before = [
        "podman-openclaw-postgres.service"
        "podman-openclaw-keycloak.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "openclaw-secrets-network-create" ''
          ${pkgs.podman}/bin/podman network exists ${keycloakCfg.network.name} || \
          ${pkgs.podman}/bin/podman network create \
            --driver bridge \
            --subnet ${keycloakCfg.network.subnet} \
            --gateway ${keycloakCfg.network.gateway} \
            --internal \
            ${keycloakCfg.network.name}
        '';
        ExecStop = "${pkgs.podman}/bin/podman network rm -f ${keycloakCfg.network.name} || true";
      };
    };

    # PostgreSQL container for Keycloak
    systemd.services.podman-openclaw-postgres = {
      description = "PostgreSQL for OpenClaw Keycloak";
      after = [ "podman.service" "openclaw-secrets-network.service" ];
      requires = [ "podman.service" "openclaw-secrets-network.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStart = pkgs.writeShellScript "openclaw-postgres-start" ''
          set -euo pipefail

          # Read password from file
          POSTGRES_PASSWORD="$(cat ${keycloakCfg.postgres.passwordFile})"

          exec ${pkgs.podman}/bin/podman run \
            --name openclaw-postgres \
            --replace \
            --network ${keycloakCfg.network.name} \
            --volume "${keycloakCfg.dataDir}/postgres:/var/lib/postgresql/data:rw" \
            --env "POSTGRES_DB=${keycloakCfg.postgres.database}" \
            --env "POSTGRES_USER=${keycloakCfg.postgres.user}" \
            --env "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
            --health-cmd "pg_isready -U ${keycloakCfg.postgres.user} -d ${keycloakCfg.postgres.database}" \
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

        ExecStop = "${pkgs.podman}/bin/podman stop -t 30 openclaw-postgres";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f openclaw-postgres || true";
      };
    };

    # Keycloak container
    systemd.services.podman-openclaw-keycloak = {
      description = "Keycloak Identity Provider for OpenClaw";
      after = [
        "podman.service"
        "openclaw-secrets-network.service"
        "podman-openclaw-postgres.service"
      ];
      requires = [
        "podman.service"
        "openclaw-secrets-network.service"
        "podman-openclaw-postgres.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "10s";

        ExecStartPre = pkgs.writeShellScript "openclaw-keycloak-wait-postgres" ''
          # Wait for PostgreSQL to be ready
          for i in $(seq 1 30); do
            if ${pkgs.podman}/bin/podman exec openclaw-postgres pg_isready -U ${keycloakCfg.postgres.user} -d ${keycloakCfg.postgres.database} >/dev/null 2>&1; then
              echo "PostgreSQL is ready"
              exit 0
            fi
            echo "Waiting for PostgreSQL... ($i/30)"
            sleep 2
          done
          echo "PostgreSQL failed to become ready"
          exit 1
        '';

        ExecStart = pkgs.writeShellScript "openclaw-keycloak-start" ''
          set -euo pipefail

          # Read passwords from files
          KEYCLOAK_ADMIN_PASSWORD="$(cat ${keycloakCfg.adminPasswordFile})"
          KC_DB_PASSWORD="$(cat ${keycloakCfg.postgres.passwordFile})"

          exec ${pkgs.podman}/bin/podman run \
            --name openclaw-keycloak \
            --replace \
            --network ${keycloakCfg.network.name} \
            --publish "127.0.0.1:${toString keycloakCfg.httpPort}:8080" \
            --volume "${realmConfig}:/opt/keycloak/data/import/openclaw-realm.json:ro" \
            --env "KEYCLOAK_ADMIN=${keycloakCfg.adminUser}" \
            --env "KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_ADMIN_PASSWORD" \
            --env "KC_DB=postgres" \
            --env "KC_DB_URL=jdbc:postgresql://openclaw-postgres:5432/${keycloakCfg.postgres.database}" \
            --env "KC_DB_USERNAME=${keycloakCfg.postgres.user}" \
            --env "KC_DB_PASSWORD=$KC_DB_PASSWORD" \
            --env "KC_HOSTNAME=${keycloakCfg.hostname}" \
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

        ExecStop = "${pkgs.podman}/bin/podman stop -t 60 openclaw-keycloak";
        ExecStopPost = "${pkgs.podman}/bin/podman rm -f openclaw-keycloak || true";
      };
    };

    # Service to initialize Keycloak realm and create client secrets
    # This runs once after Keycloak is up and creates secrets for injectors
    systemd.services.openclaw-keycloak-init = {
      description = "Initialize OpenClaw Keycloak Realm and Client Secrets";
      after = [ "podman-openclaw-keycloak.service" ];
      requires = [ "podman-openclaw-keycloak.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        ExecStart = pkgs.writeShellScript "openclaw-keycloak-init" ''
          set -euo pipefail

          KEYCLOAK_URL="http://127.0.0.1:${toString keycloakCfg.httpPort}"
          KEYCLOAK_ADMIN="${keycloakCfg.adminUser}"
          KEYCLOAK_ADMIN_PASSWORD="$(cat ${keycloakCfg.adminPasswordFile})"

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

          # Check if openclaw realm exists, create if not
          if ! ${pkgs.curl}/bin/curl -sf \
            "$KEYCLOAK_URL/admin/realms/openclaw" \
            -H "Authorization: Bearer $ADMIN_TOKEN" >/dev/null 2>&1; then
            echo "Creating openclaw realm..."
            ${pkgs.curl}/bin/curl -sf -X POST \
              "$KEYCLOAK_URL/admin/realms" \
              -H "Authorization: Bearer $ADMIN_TOKEN" \
              -H "Content-Type: application/json" \
              -d '{"realm": "openclaw", "enabled": true, "sslRequired": "none"}'
          fi

          # Create client secrets directory
          mkdir -p /var/lib/openclaw/keycloak/client-secrets
          chmod 700 /var/lib/openclaw/keycloak/client-secrets

          # Create service accounts for each instance
          ${concatStringsSep "\n" (builtins.map (name: ''
            echo "Setting up client for instance: ${name}"
            CLIENT_ID="openclaw-injector-${name}"

            # Check if client exists
            CLIENT_UUID=$(${pkgs.curl}/bin/curl -sf \
              "$KEYCLOAK_URL/admin/realms/openclaw/clients?clientId=$CLIENT_ID" \
              -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.[0].id // empty')

            if [ -z "$CLIENT_UUID" ]; then
              echo "Creating client $CLIENT_ID..."
              ${pkgs.curl}/bin/curl -sf -X POST \
                "$KEYCLOAK_URL/admin/realms/openclaw/clients" \
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
                "$KEYCLOAK_URL/admin/realms/openclaw/clients?clientId=$CLIENT_ID" \
                -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.[0].id')
            fi

            # Get or regenerate client secret
            CLIENT_SECRET=$(${pkgs.curl}/bin/curl -sf \
              "$KEYCLOAK_URL/admin/realms/openclaw/clients/$CLIENT_UUID/client-secret" \
              -H "Authorization: Bearer $ADMIN_TOKEN" | ${pkgs.jq}/bin/jq -r '.value')

            # Store client secret for injector
            echo "$CLIENT_SECRET" > "/var/lib/openclaw/keycloak/client-secrets/${name}.secret"
            chmod 400 "/var/lib/openclaw/keycloak/client-secrets/${name}.secret"
            echo "Client secret stored for ${name}"
          '') (builtins.attrNames enabledInstances))}

          echo "Keycloak initialization complete"
        '';
      };
    };
  };
}
