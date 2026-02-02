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
      default = 8192;  # 4GB per vCPU
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

    tailscale = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable Tailscale for secure remote access via tailnet";
      };

      loginServer = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://headscale.example.com";
        description = "Headscale/Tailscale control server URL. If null, uses default Tailscale.";
      };
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "openclaw-vm";

    # Restrict fw_cfg sysfs to root only - systemd reads as root, then places
    # credentials in service-specific directory. Prevents compromised agent
    # from reading raw credentials via /sys/firmware/qemu_fw_cfg/
    services.udev.extraRules = ''
      SUBSYSTEM=="firmware", DRIVER=="qemu_fw_cfg", MODE="0400", OWNER="root", GROUP="root"
    '';

    # Static IP configuration for TAP networking
    # Interface is named enp0s4 by systemd predictable naming (virtio-net-pci on slot 4)
    networking.useDHCP = false;
    networking.interfaces.enp0s4 = {
      ipv4.addresses = [{
        address = "10.88.0.2";
        prefixLength = 24;
      }];
    };
    networking.defaultGateway = {
      address = "10.88.0.1";
      interface = "enp0s4";
    };
    networking.nameservers = [ "10.88.0.1" ];

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ cfg.gatewayPort ];
      # Trust tailscale interface for inbound connections
      trustedInterfaces = lib.optionals cfg.tailscale.enable [ "tailscale0" ];
    };

    # Tailscale for secure remote access
    # extraDaemonFlags overrides state path to use persistent volume (survives VM rebuilds)
    services.tailscale = lib.mkIf cfg.tailscale.enable {
      enable = true;
      # Auth key injected via fw_cfg, read by systemd LoadCredential
      authKeyFile = "/run/credentials/tailscaled.service/tailscale-authkey";
      extraUpFlags = lib.optionals (cfg.tailscale.loginServer != null) [
        "--login-server" cfg.tailscale.loginServer
      ] ++ [
        "--hostname" "openclaw-vm"
      ];
      # Use persistent volume for state (--state flag overrides default /var/lib/tailscale)
      extraDaemonFlags = [ "--state=/var/lib/openclaw/tailscale/tailscaled.state" ];
    };

    # Configure tailscaled to read auth key from fw_cfg credential
    systemd.services.tailscaled = lib.mkIf cfg.tailscale.enable {
      serviceConfig = {
        LoadCredential = [ "tailscale-authkey" ];
        # Don't create unused /var/lib/tailscale (we use /var/lib/openclaw/tailscale)
        StateDirectory = lib.mkForce "";
      };
    };

    # Tailscale Serve: auto-configure HTTPS proxy to gateway
    # Runs once after tailscale is online, persists in tailscale state
    systemd.services.tailscale-serve = lib.mkIf cfg.tailscale.enable {
      description = "Configure Tailscale Serve for OpenClaw Gateway";
      after = [ "tailscaled.service" ];
      requires = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      # Only run if serve not already configured
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg https+insecure://localhost:${toString cfg.gatewayPort}";
        # Retry if tailscale not ready yet
        Restart = "on-failure";
        RestartSec = 5;
        RestartMaxDelaySec = "60s";
      };
    };

    # OpenClaw user
    users.users.openclaw = {
      isNormalUser = true;
      home = "/home/openclaw";
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
    ];

    # OpenClaw gateway service
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway";
      after = [ "network-online.target" ]
        ++ lib.optionals cfg.tailscale.enable [ "tailscaled.service" "tailscale-serve.service" ];
      wants = [ "network-online.target" ];
      # Fail-closed: gateway requires tailscale when enabled
      requires = lib.optionals cfg.tailscale.enable [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "openclaw";
        WorkingDirectory = "/var/lib/openclaw/workspace";
        StateDirectory = "openclaw";
        ExecStart = "${openclaw-pkg}/bin/openclaw gateway --port ${toString cfg.gatewayPort}";
        Restart = "always";
        RestartSec = 5;
        RestartSteps = 5;
        RestartMaxDelaySec = "60s";
        WatchdogSec = "30s";
        # Load credentials via fw_cfg
        LoadCredential = "openclaw-config";
        # %d = credentials directory
        Environment = [
          "HOME=/home/openclaw"
          "XDG_CONFIG_HOME=/home/openclaw/.config"
          "OPENCLAW_CONFIG_PATH=%d/openclaw-config"
          "OPENCLAW_STATE_DIR=/var/lib/openclaw"
        ];
      };
    };

    # Auto-login for easy access
    services.getty.autologinUser = "openclaw";

    # Enable getty on ttyS1 for console socket access
    systemd.services."serial-getty@ttyS1".enable = true;

    # microvm configuration
    microvm = {
      hypervisor = "qemu";
      vcpu = cfg.vcpu;
      mem = cfg.mem;

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
        size = 16384;  # 16 GB for workspace and logs
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
    systemd.tmpfiles.rules = [
      "d /home/openclaw/.openclaw 0755 openclaw users -"
      "d /home/openclaw/.config 0755 openclaw users -"
      "d /var/lib/openclaw/workspace 0755 openclaw users -"
      "f /var/lib/openclaw/workspace/AGENTS.md 0644 openclaw users -"
      "f /var/lib/openclaw/workspace/SOUL.md 0644 openclaw users -"
      "f /var/lib/openclaw/workspace/TOOLS.md 0644 openclaw users -"
    ] ++ lib.optionals cfg.tailscale.enable [
      # Tailscale state on persistent volume (survives rebuilds)
      "d /var/lib/openclaw/tailscale 0700 root root -"
    ];
  };
}
