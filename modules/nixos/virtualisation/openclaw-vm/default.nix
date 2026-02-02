# OpenClaw MicroVM Host Configuration
# This module configures the host to run the openclaw-vm microVM.
# The guest configuration is defined in ./guest.nix
#
# Architecture (per PROPOSAL-1):
# - Host runs zero-trust infrastructure (Keycloak + OpenBao)
# - Host injector writes secrets to /run/openclaw-vm/secrets/
# - microVM mounts secrets via 9p share
# - Gateway accessible at localhost:18789 via QEMU port forwarding
{ config
, options
, pkgs
, lib ? pkgs.lib
, nix-openclaw
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw-vm;
  hasMicrovm = options ? microvm;

  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    optionalAttrs
    types
    ;
in
{
  options.CUSTOM.virtualisation.openclaw-vm = {
    enable = mkEnableOption "OpenClaw in microVM";

    # Gateway configuration
    gatewayPort = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for OpenClaw gateway (forwarded to VM)";
    };

    # Resource limits
    memory = mkOption {
      type = types.int;
      default = 8192;  # 4GB per vCPU
      description = "Memory allocation in MiB for the microVM";
    };

    vcpu = mkOption {
      type = types.int;
      default = 2;
      description = "Virtual CPU count";
    };

    # Secrets integration
    secrets = {
      enable = mkEnableOption "Inject secrets from host zero-trust infrastructure";

      mountPoint = mkOption {
        type = types.path;
        default = /run/openclaw-vm/secrets;
        description = "Host path where injector writes secrets (shared to VM via 9p)";
      };

      sopsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to sops secrets file for fallback secrets";
      };

      ageKeyFile = mkOption {
        type = types.path;
        default = /var/lib/sops-nix/keys.txt;
        description = "Path to age key file for sops decryption";
      };
    };

    # State management
    stateDir = mkOption {
      type = types.path;
      default = /var/lib/microvms/openclaw-vm/state;
      description = "Host path for VM persistent state volume";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Host-side config (works without microvm module)
    {
      # Create secrets directory on tmpfs
      systemd.tmpfiles.rules = [
        "d ${toString cfg.secrets.mountPoint} 0700 root root -"
        "d ${toString cfg.stateDir} 0755 root root -"
      ];

      # Assertions
      assertions = [
        {
          assertion = hasMicrovm;
          message = "OpenClaw VM requires microvm.nix. Ensure microvm module is available.";
        }
      ];
    }

    # microvm-specific config (only when microvm module is available)
    (optionalAttrs hasMicrovm {
      microvm.vms.openclaw-vm = {
        inherit pkgs;
        specialArgs = { inherit nix-openclaw; };

        config = { config, ... }: {
          imports = [ ./guest.nix ];

          CUSTOM.virtualisation.openclaw-vm.guest = {
            vcpu = cfg.vcpu;
            mem = cfg.memory;
            gatewayPort = cfg.gatewayPort;
            secrets.mountPoint = cfg.secrets.mountPoint;
          };
        };
      };

      microvm.host.enable = true;

      # Ensure microvm starts after secrets are ready
      # The injector service (if using zero-trust) writes to secrets.mountPoint
      systemd.services."microvm@openclaw-vm" = {
        # Wait for secrets directory to exist with config file
        unitConfig.ConditionPathExists = "${toString cfg.secrets.mountPoint}/openclaw.json";
      };
    })

    # sops-nix secrets configuration (fallback when zero-trust not available)
    (mkIf (cfg.secrets.enable && cfg.secrets.sopsFile != null) {
      sops.secrets."openclaw/gateway-token" = {
        sopsFile = cfg.secrets.sopsFile;
        key = "gateway_token";
      };

      sops.age.keyFile = lib.mkDefault cfg.secrets.ageKeyFile;

      # Generate openclaw.json config from sops secrets
      sops.templates."openclaw-vm-config" = {
        content = builtins.toJSON {
          gateway = {
            mode = "local";
            auth = {
              token = config.sops.placeholder."openclaw/gateway-token";
            };
          };
        };
        path = "${toString cfg.secrets.mountPoint}/openclaw.json";
        mode = "0400";
        owner = "root";
        group = "root";
      };
    })
  ]);
}
