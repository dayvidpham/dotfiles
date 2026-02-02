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

    secrets.mountPoint = mkOption {
      type = types.path;
      default = /run/openclaw-vm/secrets;
      description = "Host path where secrets are mounted (used by 9p share)";
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "openclaw-vm";

    # Network access for safemolt
    networking.useDHCP = true;
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ cfg.gatewayPort ];
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
    ];

    # OpenClaw gateway service
    systemd.services.openclaw-gateway = {
      description = "OpenClaw Gateway";
      after = [ "network-online.target" "run-secrets.mount" ];
      wants = [ "network-online.target" ];
      requires = [ "run-secrets.mount" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "openclaw";
        WorkingDirectory = "/var/lib/openclaw/workspace";
        StateDirectory = "openclaw";
        ExecStartPre = "${openclaw-pkg}/bin/openclaw onboard --non-interactive --accept-risk --mode local || true";
        ExecStart = "${openclaw-pkg}/bin/openclaw gateway --config /run/secrets/openclaw.json";
        Restart = "always";
        RestartSec = 5;
        Environment = [
          "HOME=/home/openclaw"
        ];
      };
    };

    # Auto-login for easy access
    services.getty.autologinUser = "openclaw";

    # microvm configuration
    microvm = {
      hypervisor = "qemu";
      vcpu = cfg.vcpu;
      mem = cfg.mem;

      # User-mode networking with port forwarding
      interfaces = [{
        type = "user";
        id = "eth0";
        mac = "02:00:00:00:00:01";
      }];

      # Forward gateway port to host
      forwardPorts = [{
        from = "host";
        host.port = cfg.gatewayPort;
        guest.port = cfg.gatewayPort;
      }];

      # Persistent state volume
      volumes = [{
        mountPoint = "/var/lib/openclaw";
        image = "openclaw-state.img";
        size = 256;
      }];

      # 9p share for secrets from host
      shares = [{
        tag = "secrets";
        source = toString cfg.secrets.mountPoint;
        mountPoint = "/run/secrets";
        proto = "9p";
      }];
    };

    # 9p mount for secrets at /run/secrets
    fileSystems."/run/secrets" = {
      device = "secrets";
      fsType = "9p";
      options = [ "trans=virtio" "version=9p2000.L" "ro" ];
    };

    # Create directories for openclaw state
    systemd.tmpfiles.rules = [
      "d /home/openclaw/.openclaw 0755 openclaw users -"
      "d /home/openclaw/.config 0755 openclaw users -"
      "d /var/lib/openclaw/workspace 0755 openclaw users -"
      "f /var/lib/openclaw/workspace/AGENTS.md 0644 openclaw users -"
      "f /var/lib/openclaw/workspace/SOUL.md 0644 openclaw users -"
      "f /var/lib/openclaw/workspace/TOOLS.md 0644 openclaw users -"
    ];
  };
}
