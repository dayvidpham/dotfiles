# OpenClaw MicroVM Guest Configuration
# Simple microvm that runs openclaw gateway with network access to safemolt
{ config
, pkgs
, lib ? pkgs.lib
, nix-openclaw
, ...
}:
let
  inherit (lib)
    mkOption
    types
    ;

  cfg = config.CUSTOM.virtualisation.openclaw-vm.guest;
  openclaw-pkg = nix-openclaw.packages.${pkgs.system}.openclaw;
  debug-tailscale = import ./debug-tailscale.nix { inherit pkgs; };
in
{
  options.CUSTOM.virtualisation.openclaw-vm.guest = {
    vcpu = mkOption {
      type = types.int;
      default = 2;
      description = "Number of virtual CPUs";
    };

    mem = mkOption {
      type = types.int;
      default = 8192;  # 4096 MiB per vCPU with default 2 vCPUs
      description = "Memory allocation in MiB";
    };

    gatewayPort = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for the OpenClaw gateway";
    };

    devMode = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use virtiofs for /nix/store (instant rebuilds, not portable).
        When false, uses erofs without dedupe (faster builds, portable).
      '';
    };

    # Network configuration (passed from host)
    network = {
      vmAddress = mkOption {
        type = types.str;
        default = "10.88.0.2";
        description = "VM IP address (should match host cfg.network.vmAddress)";
      };

      gatewayAddress = mkOption {
        type = types.str;
        default = "10.88.0.1";
        description = "Gateway/host bridge IP address";
      };

      prefixLength = mkOption {
        type = types.int;
        default = 24;
        description = "Network prefix length";
      };
    };

    # State volume configuration
    stateVolumeSize = mkOption {
      type = types.int;
      default = 16384;
      description = "Size of persistent state volume in MiB (default 16 GiB)";
    };

    # VSOCK configuration for host-guest communication
    vsock = {
      cid = mkOption {
        type = types.int;
        default = 4;  # CID 3 used by llm-sandbox
        description = ''
          VSOCK Context ID for this VM.
          CID 0 = hypervisor, 1 = loopback, 2 = host, 3+ = guests.
        '';
      };

      port = mkOption {
        type = types.port;
        default = 18789;
        description = "VSOCK port for gateway proxy (matches gateway port for clarity)";
      };
    };

    # Tailscale configuration for remote access
    tailscale = {
      enable = lib.mkEnableOption "Tailscale for secure remote access via tailnet";

      hostname = mkOption {
        type = types.str;
        default = "openclaw-vm";
        description = "Hostname for this machine on the tailnet";
      };

      loginServer = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Custom control server URL (e.g., Headscale). If null, uses Tailscale's default servers.";
        example = "https://headscale.example.com";
      };

      serve = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Tailscale Serve to expose gateway via HTTPS";
        };
      };

      advertiseTags = mkOption {
        type = types.listOf types.str;
        default = [ "tag:openclaw-vm" ];
        description = "ACL tags to advertise for this node (requires pre-authorized auth key with these tags)";
      };

      exitNode = mkOption {
        type = types.nullOr types.str;
        default = "portal";
        description = "Exit node hostname to route traffic through. Set to null to disable.";
        example = "exit-node.tail1234.ts.net";
      };
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "openclaw-vm";

    # Restrict fw_cfg sysfs to root only - systemd reads as root, then places
    # credentials in service-specific directory. Prevents compromised agent
    # from reading raw credentials via /sys/firmware/qemu_fw_cfg/
    # NOTE: Cannot blacklist qemu_fw_cfg module - systemd needs sysfs to import credentials
    services.udev.extraRules = ''
      SUBSYSTEM=="firmware", DRIVER=="qemu_fw_cfg", MODE="0400", OWNER="root", GROUP="root"
    '';

    # Static IP configuration for TAP networking
    networking.useDHCP = false;
    # TAP interface appears as enp0s4 (predictable naming: PCI slot 0, device 4)
    networking.interfaces.enp0s4 = {
      ipv4.addresses = [{
        address = cfg.network.vmAddress;
        prefixLength = cfg.network.prefixLength;
      }];
    };
    networking.defaultGateway = {
      address = cfg.network.gatewayAddress;
      interface = "enp0s4";
    };
    # Use host as DNS resolver (more secure - uses host's encrypted DNS config)
    networking.nameservers = [ cfg.network.gatewayAddress ];

    networking.firewall = {
      enable = true;
      # Gateway binds to localhost only (VSOCK handles host access)
      # No TCP ports need to be exposed on TAP interface
      allowedTCPPorts = [ ];
      # Trust Tailscale interface for inbound connections when enabled
      trustedInterfaces = lib.optionals cfg.tailscale.enable [ "tailscale0" ];
    };

    # Tailscale for secure remote access
    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      # Auth key injected via fw_cfg, read by systemd LoadCredential
      authKeyFile = "/run/credentials/tailscaled.service/tailscale-authkey";
      extraUpFlags = [
        "--hostname" cfg.tailscale.hostname
      ] ++ lib.optionals (cfg.tailscale.loginServer != null) [
        "--login-server" cfg.tailscale.loginServer
      ] ++ lib.optionals (cfg.tailscale.advertiseTags != []) [
        "--advertise-tags" (lib.concatStringsSep "," cfg.tailscale.advertiseTags)
      ] ++ lib.optionals (cfg.tailscale.exitNode != null) [
        "--exit-node" cfg.tailscale.exitNode
      ];
      # Use persistent volume for state (survives VM rebuilds)
      extraDaemonFlags = [ "--state=/var/lib/openclaw/tailscale/tailscaled.state" ];
    };

    # Configure tailscaled to read auth key from fw_cfg credential
    systemd.services.tailscaled = lib.mkIf cfg.tailscale.enable {
      serviceConfig = {
        LoadCredential = [ "tailscale-authkey" ];
        # State in persistent volume, not default /var/lib/tailscale
        StateDirectory = lib.mkForce "";
      };
    };

    # Tailscale Serve: expose gateway via HTTPS
    # Runs after tailscale is online, configures serve to proxy to gateway
    systemd.services.tailscale-serve = lib.mkIf (cfg.tailscale.enable && cfg.tailscale.serve.enable) {
      description = "Configure Tailscale Serve for OpenClaw Gateway";
      after = [ "tailscaled.service" "network-online.target" ];
      requires = [ "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # Wait for tailscale to be ready before configuring serve
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Serve HTTPS, proxy to gateway's localhost port
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://localhost:${toString cfg.gatewayPort}";
        # Retry if tailscale not ready yet
        Restart = "on-failure";
        RestartSec = 5;
        RestartMaxDelaySec = "60s";
      };
    };

    # Security: Tailscale state directory with strict permissions
    # Prevents openclaw user from reading node keys
    systemd.tmpfiles.settings."10-tailscale" = lib.mkIf cfg.tailscale.enable {
      "/var/lib/openclaw/tailscale" = {
        d = {
          mode = "0700";
          user = "root";
          group = "root";
        };
      };
    };

    # Shared group for workspace access - both users can read/write workspace files
    users.groups.openclaw-shared = {};

    # Gateway user group
    users.groups.openclaw-gateway = {};

    # Gateway user (system user) - runs gateway service, owns credentials
    # System users cannot login interactively and have no home directory by default
    users.users.openclaw-gateway = {
      isSystemUser = true;
      group = "openclaw-gateway";
      extraGroups = [ "openclaw-shared" ];
      description = "OpenClaw Gateway Service";
    };

    # Agent/interactive user (normal user) - interactive sessions, agent processes
    users.users.openclaw = {
      isNormalUser = true;
      home = "/home/openclaw";
      extraGroups = [ "openclaw-shared" ];
      description = "OpenClaw Agent";
    };

    # Packages
    environment.systemPackages = [
      openclaw-pkg
      pkgs.curl
      pkgs.jq
      pkgs.git
      pkgs.bun        # JavaScript runtime
      pkgs.uv         # Python package manager
      debug-tailscale # Diagnostic script for Tailscale debugging
    ];

    # OpenClaw gateway service
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway";
      after = [ "network-online.target" ]
        ++ lib.optionals cfg.tailscale.enable [ "tailscaled.service" "tailscale-serve.service" ];
      wants = [ "network-online.target" ];
      # When tailscale enabled, require it for fail-closed security
      requires = lib.optionals cfg.tailscale.enable [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      # Crash protection - prevent resource exhaustion from crash loops
      # 5 failures in 5 minutes triggers cooldown
      startLimitBurst = 5;
      startLimitIntervalSec = 300;

      serviceConfig = {
        Type = "simple";
        User = "openclaw-gateway";
        Group = "openclaw-gateway";
        WorkingDirectory = "/var/lib/openclaw/workspace";
        StateDirectory = "openclaw";
        # Auto: tries loopback first, falls back to LAN if needed
        # VSOCK connections appear as localhost, so loopback binding works
        ExecStart = "${openclaw-pkg}/bin/openclaw gateway --bind auto --port ${toString cfg.gatewayPort}";
        Restart = "always";
        RestartSec = 5;
        RestartSteps = 5;
        RestartMaxDelaySec = "60s";
        # Disabled: openclaw gateway doesn't implement systemd watchdog notifications
        # WatchdogSec = "30s";

        # Load credentials via fw_cfg
        LoadCredential = "openclaw-config";

        # Process isolation - hide gateway from agent's /proc view
        # Prevents compromised agent from seeing gateway process or terminating it
        ProtectProc = "invisible";
        ProcSubset = "pid";
        NoNewPrivileges = true;

        # Filesystem isolation
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;

        # Kernel hardening
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;

        # Namespace restrictions
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;

        # Memory protection
        # NOTE: MemoryDenyWriteExecute incompatible with Node.js V8 JIT
        # V8 requires mprotect(PROT_EXEC) on previously writable memory
        LockPersonality = true;

        # Capabilities
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";

        # System call filtering
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
        SystemCallArchitectures = "native";

        # %d = credentials directory
        # HOME points to gateway's config dir, not agent's home
        Environment = [
          "HOME=/var/lib/openclaw"
          "XDG_CONFIG_HOME=/var/lib/openclaw/.config"
          "OPENCLAW_CONFIG_PATH=%d/openclaw-config"
          "OPENCLAW_STATE_DIR=/var/lib/openclaw"
        ];
      };
    };

    # VSOCK gateway proxy - forwards VSOCK connections to gateway's localhost port
    # This allows host connections via VSOCK to appear as localhost to the gateway
    systemd.services.vsock-gateway-proxy = {
      description = "VSOCK to Gateway Localhost Proxy";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # Listen on VSOCK port, forward to gateway's localhost port
        ExecStart = "${pkgs.socat}/bin/socat VSOCK-LISTEN:${toString cfg.vsock.port},reuseaddr,fork TCP:127.0.0.1:${toString cfg.gatewayPort}";
        Restart = "always";
        RestartSec = "1s";
        # Hardening - this is just a network proxy
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    # Auto-login as root for debugging/admin access via console
    services.getty.autologinUser = "root";

    # Security: no passwordless sudo
    security.sudo.wheelNeedsPassword = true;

    # Security: restrict systemctl/journalctl access for openclaw users
    # Prevents compromised agent from enumerating services or reading system logs
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        // Deny systemd status/control queries for openclaw users
        if (action.id.indexOf("org.freedesktop.systemd1") === 0 &&
            (subject.user === "openclaw" || subject.user === "openclaw-gateway")) {
          return polkit.Result.NO;
        }
        // Deny reading system journal
        if (action.id === "org.freedesktop.login1.journal-read" &&
            (subject.user === "openclaw" || subject.user === "openclaw-gateway")) {
          return polkit.Result.NO;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';

    # Enable getty on ttyS1 for console socket access
    systemd.services."serial-getty@ttyS1".enable = true;

    # microvm configuration
    microvm = {
      hypervisor = "qemu";
      vcpu = cfg.vcpu;
      mem = cfg.mem;

      # VSOCK for host-guest communication (gateway access without TCP/IP)
      vsock = {
        cid = cfg.vsock.cid;
      };

      # Add console socket for interactive access (ttyS1)
      # Connect with: socat -,raw,echo=0 UNIX-CONNECT:console.sock
      qemu.extraArgs = [
        "-chardev" "socket,id=console,path=console.sock,server=on,wait=off"
        "-device" "isa-serial,chardev=console"
      ];

      # TAP networking for proper isolation
      interfaces = [{
        type = "tap";
        id = "vm-openclaw";
        mac = "02:00:00:00:00:01";
      }];

      # Persistent state volume
      volumes = [{
        mountPoint = "/var/lib/openclaw";
        image = "openclaw-state.img";
        size = cfg.stateVolumeSize;
      }];

      # Shares configuration
      shares = lib.optionals cfg.devMode [{
        # devMode: mount host's /nix/store via virtiofs (instant rebuilds)
        # Note: /nix/store is read-only by NixOS design (no explicit ro flag needed)
        # virtiofs respects host permissions; /nix/store is immutable on the host
        tag = "nix-store";
        source = "/nix/store";
        mountPoint = "/nix/store";
        proto = "virtiofs";
      }];

      # devMode: don't embed /nix/store in image (use virtiofs instead)
      storeOnDisk = !cfg.devMode;

      # non-devMode: use erofs without dedupe for faster multi-threaded builds
      storeDiskErofsFlags = lib.mkIf (!cfg.devMode) [ "-zlz4hc" "-Eztailpacking" ];
    };

    # Create directories for openclaw state
    # Dual-user model:
    # - openclaw-gateway: system user that runs gateway, owns credentials and config
    # - openclaw: normal user for interactive/agent sessions
    # - openclaw-shared: group for shared workspace access
    systemd.tmpfiles.rules = [
      # Gateway user config dirs (owned by gateway, not accessible to agent)
      "d /var/lib/openclaw 0755 openclaw-gateway openclaw-gateway -"
      "d /var/lib/openclaw/.config 0755 openclaw-gateway openclaw-gateway -"
      "d /var/lib/openclaw/.openclaw 0755 openclaw-gateway openclaw-gateway -"
      "d /var/lib/openclaw/.openclaw/canvas 0755 openclaw-gateway openclaw-gateway -"
      "d /var/lib/openclaw/cron 0755 openclaw-gateway openclaw-gateway -"

      # Shared workspace with setgid for group ownership
      # Mode 2775: rwxrwsr-x - setgid ensures new files inherit openclaw-shared group
      # Both gateway and agent can read/write, but gateway's credentials stay protected
      "d /var/lib/openclaw/workspace 2775 root openclaw-shared -"

      # Agent user home directories
      "d /home/openclaw 0755 openclaw users -"
      "d /home/openclaw/.openclaw 0755 openclaw users -"
      "d /home/openclaw/.config 0755 openclaw users -"

      # Optional workspace files (group-writable for collaboration)
      "f /var/lib/openclaw/workspace/AGENTS.md 0664 root openclaw-shared -"
      "f /var/lib/openclaw/workspace/SOUL.md 0664 root openclaw-shared -"
      "f /var/lib/openclaw/workspace/TOOLS.md 0664 root openclaw-shared -"
    ];
  };
}
