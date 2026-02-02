# OpenClaw MicroVM Host Configuration
# This module configures the host to run the openclaw-vm microVM.
# The guest configuration is defined in ./guest.nix
#
# Architecture:
# - Host runs zero-trust infrastructure (Keycloak + OpenBao)
# - Secrets passed to VM via fw_cfg (microvm.credentials)
# - Guest services load credentials via systemd LoadCredential
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

  # Console access script for the microVM
  vm-console = pkgs.writeShellScriptBin "openclaw-vm-console" ''
    set -euo pipefail

    SOCKET_PATH="/var/lib/microvms/openclaw-vm/console.sock"

    if [[ ! -S "$SOCKET_PATH" ]]; then
        echo "Error: Console socket not found at $SOCKET_PATH" >&2
        echo "Is the VM running? Check: systemctl status microvm@openclaw-vm" >&2
        exit 1
    fi

    echo "Connecting to openclaw-vm console..."
    echo "Press Ctrl+] to exit"
    echo "---"

    exec ${pkgs.socat}/bin/socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:"$SOCKET_PATH"
  '';
in
{
  options.CUSTOM.virtualisation.openclaw-vm = {
    enable = mkEnableOption "OpenClaw in microVM";

    devMode = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use virtiofs for /nix/store instead of embedding in erofs image.
        Enables instant rebuilds but requires host's /nix/store at runtime.
        Disable for portable/CI builds (uses erofs without dedupe for faster builds).
      '';
    };

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

      sopsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to sops secrets file for fallback secrets";
      };

      ageKeyFile = mkOption {
        type = types.path;
        default = /var/lib/sops-nix/keys.txt;
        description = ''
          DEPRECATED: This option is no longer used. Configure sops.age.keyFile
          directly in your host configuration if needed.

          Path to age key file for sops decryption.
        '';
      };
    };

    # Tailscale integration (host-side config)
    tailscale = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Tailscale for secure remote access. Requires secrets.enable and sopsFile.";
      };

      authKeySecret = mkOption {
        type = types.str;
        default = "tailscale_authkey";
        description = "Key name in sops file for the Tailscale auth key";
      };

      loginServer = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://headscale.example.com";
        description = "Headscale/Tailscale control server URL. If null, uses default Tailscale.";
      };
    };

    # State management
    stateDir = mkOption {
      type = types.path;
      default = /var/lib/microvms/openclaw-vm/state;
      description = "Host path for VM persistent state volume";
    };

    # Network configuration
    network = {
      bridgeName = mkOption {
        type = types.str;
        default = "br-openclaw";  # Max 15 chars for Linux interface names
        description = "Name of the bridge interface for VM networking";
      };

      bridgeAddress = mkOption {
        type = types.str;
        default = "10.88.0.1/24";
        description = "Host bridge IP address and subnet";
      };

      vmAddress = mkOption {
        type = types.str;
        default = "10.88.0.2";
        description = "VM IP address (used for port forwarding)";
      };

      tapInterface = mkOption {
        type = types.str;
        default = "vm-openclaw";
        description = "Name of the TAP interface (must match guest.nix)";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Host-side config (works without microvm module)
    {
      # Dedicated group for secrets access
      users.groups.openclaw-secrets = {};

      # Grant microvm user access to secrets via group membership
      users.users.microvm.extraGroups = [ "openclaw-secrets" ];

      # State dir: 0750 root:kvm - microvm user (in kvm group) needs access
      systemd.tmpfiles.rules = [
        "d ${toString cfg.stateDir} 0750 root kvm -"
      ];

      # Console access script
      environment.systemPackages = [ vm-console ];

      # Assertions
      assertions = [
        {
          assertion = hasMicrovm;
          message = "OpenClaw VM requires microvm.nix. Ensure microvm module is available.";
        }
        {
          assertion = !(
            cfg.secrets.enable &&
            cfg.secrets.sopsFile != null &&
            config.CUSTOM.virtualisation.openclaw.zeroTrust.injector.vmMode.enable or false
          );
          message = ''
            Cannot use both sops.templates secrets (cfg.secrets.sopsFile) and injector.vmMode simultaneously.
            Both would try to provide credentials to the microVM.
            Choose one:
            - For zero-trust injection: enable CUSTOM.virtualisation.openclaw.zeroTrust.injector.vmMode
            - For sops-only: set cfg.secrets.sopsFile and disable injector.vmMode
          '';
        }
        {
          assertion = cfg.tailscale.enable -> (cfg.secrets.enable && cfg.secrets.sopsFile != null);
          message = "tailscale.enable requires secrets.enable and secrets.sopsFile for auth key injection";
        }
      ];

      # TAP networking configuration
      # systemd-networkd for TAP interface bridge
      systemd.network.enable = true;

      # Bridge device for microVM networking
      systemd.network.netdevs."10-microvm-openclaw" = {
        netdevConfig = {
          Kind = "bridge";
          Name = cfg.network.bridgeName;
        };
      };

      # Bridge network configuration
      systemd.network.networks."10-microvm-openclaw" = {
        matchConfig.Name = cfg.network.bridgeName;
        address = [ cfg.network.bridgeAddress ];
        linkConfig.RequiredForOnline = "no";
      };

      # Enable IP forwarding for VM networking
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
      };

      # Enable DNS forwarding for VM (systemd-resolved)
      services.resolved = {
        enable = true;
        extraConfig = ''
          # Allow DNS queries from VM network
          DNSStubListenerExtra=${lib.head (lib.splitString "/" cfg.network.bridgeAddress)}
        '';
      };

      # Attach TAP interface to bridge
      systemd.network.networks."11-microvm-openclaw-tap" = {
        matchConfig.Name = cfg.network.tapInterface;
        bridge = [ cfg.network.bridgeName ];
        linkConfig.RequiredForOnline = "no";
      };

      # nftables configuration for VM isolation
      networking.nftables.enable = true;

      networking.nftables.tables.openclaw-vm-firewall = {
        family = "inet";
        content = ''
          # OpenClaw VM Network Isolation
          # Access gateway directly at ${cfg.network.vmAddress}:${toString cfg.gatewayPort}

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;

            # Masquerade traffic from VM to internet
            ip saddr ${cfg.network.bridgeAddress} oifname != "${cfg.network.bridgeName}" masquerade
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            # Allow established/related connections
            ct state established,related accept

            # Allow forwarding to/from VM bridge
            iifname "${cfg.network.bridgeName}" accept
            oifname "${cfg.network.bridgeName}" accept

            # Drop everything else (strict isolation)
          }
        '';
      };
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
            devMode = cfg.devMode;
            tailscale = {
              enable = cfg.tailscale.enable;
              loginServer = cfg.tailscale.loginServer;
            };
          };
        };
      };

      microvm.host.enable = true;

      # Ensure microvm starts after secrets are ready
      systemd.services."microvm@openclaw-vm" = {
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
      };
    })

    # sops-nix secrets configuration (fallback when zero-trust not available)
    (mkIf (cfg.secrets.enable && cfg.secrets.sopsFile != null) {
      sops.secrets."openclaw/gateway-token" = {
        sopsFile = cfg.secrets.sopsFile;
        key = "gateway_token";
      };

      sops.secrets."openclaw/tailscale-authkey" = lib.mkIf cfg.tailscale.enable {
        sopsFile = cfg.secrets.sopsFile;
        key = cfg.tailscale.authKeySecret;
        mode = "0400";
        owner = "microvm";  # Only microvm user needs this secret
      };

      # Generate openclaw.json config from sops secrets
      # This is passed to the VM via fw_cfg credentials
      sops.templates."openclaw.json" = {
        content = builtins.toJSON {
          gateway = {
            mode = "local";
            bind = "lan";  # Bind to all interfaces (safe in isolated microvm)
            auth = {
              token = config.sops.placeholder."openclaw/gateway-token";
            };
          };
        };
        mode = "0440";
        owner = "root";
        group = "openclaw-secrets";  # microvm user is in this group
      };
    })

    # Add credentials to microvm when secrets are enabled
    (mkIf (hasMicrovm && cfg.secrets.enable && cfg.secrets.sopsFile != null) {
      microvm.vms.openclaw-vm = {
        # Pass secrets via fw_cfg (QEMU firmware configuration)
        # These become available to guest systemd services via LoadCredential
        config.microvm.credentialFiles = {
          "openclaw-config" = "/run/secrets/rendered/openclaw.json";
        } // lib.optionalAttrs cfg.tailscale.enable {
          "tailscale-authkey" = config.sops.secrets."openclaw/tailscale-authkey".path;
        };
      };
    })
  ]);
}
