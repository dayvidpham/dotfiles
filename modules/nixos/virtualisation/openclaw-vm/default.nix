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
      default = 8192;  # 4096 MiB per vCPU with default 2 vCPUs
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
          assertion = !(cfg.secrets.enable && cfg.secrets.sopsFile != null) || (options ? sops);
          message = "OpenClaw VM secrets require sops-nix module. Add sops-nix to your imports.";
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
        # Required for DNAT from localhost (127.0.0.0/8) to VM
        # Only enabled on loopback interface (more secure than conf.all)
        "net.ipv4.conf.lo.route_localnet" = 1;
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

      # Trust bridge interface in default NixOS firewall
      networking.firewall.trustedInterfaces = [ cfg.network.bridgeName ];

      # nftables configuration for port forwarding and isolation
      networking.nftables.enable = true;

      networking.nftables.tables.openclaw-vm-firewall = {
        family = "inet";
        content = ''
          # OpenClaw VM Network Isolation
          # Port forwarding from host to VM

          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;

            # Forward localhost:${toString cfg.gatewayPort} to VM (for incoming packets)
            iifname "lo" tcp dport ${toString cfg.gatewayPort} dnat ip to ${cfg.network.vmAddress}:${toString cfg.gatewayPort}
          }

          chain output {
            type nat hook output priority dstnat; policy accept;

            # Forward localhost:${toString cfg.gatewayPort} to VM (for locally-generated packets)
            ip daddr 127.0.0.1 tcp dport ${toString cfg.gatewayPort} dnat ip to ${cfg.network.vmAddress}:${toString cfg.gatewayPort}
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;

            # SNAT localhost->VM traffic so VM can respond (127.0.0.1 -> bridge IP)
            ip saddr 127.0.0.1 oifname "${cfg.network.bridgeName}" snat ip to ${lib.head (lib.splitString "/" cfg.network.bridgeAddress)}

            # Masquerade traffic from VM to internet
            ip saddr ${cfg.network.bridgeAddress} oifname != "${cfg.network.bridgeName}" masquerade
          }

          chain forward {
            type filter hook forward priority filter; policy drop;

            # Allow established/related connections (handles return traffic)
            ct state established,related accept

            # Allow VM-initiated outbound traffic
            iifname "${cfg.network.bridgeName}" accept

            # Allow DNAT'd traffic TO the VM (from localhost via bridge)
            oifname "${cfg.network.bridgeName}" accept
          }

          chain input {
            type filter hook input priority filter; policy drop;

            # Allow established/related connections
            ct state established,related accept

            # Allow all localhost traffic (required for DNAT and local services)
            iifname "lo" accept

            # Allow traffic from VM bridge (for DNS, etc.)
            iifname "${cfg.network.bridgeName}" accept

            # Everything else dropped by policy
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
            # Pass network config to ensure host and guest stay in sync
            network = {
              vmAddress = cfg.network.vmAddress;
              gatewayAddress = lib.head (lib.splitString "/" cfg.network.bridgeAddress);
              prefixLength = lib.toInt (lib.last (lib.splitString "/" cfg.network.bridgeAddress));
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

      # Generate openclaw.json config from sops secrets
      # This is passed to the VM via fw_cfg credentials
      sops.templates."openclaw.json" = {
        content = builtins.toJSON {
          gateway = {
            mode = "local";
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
        };
      };
    })
  ]);
}
