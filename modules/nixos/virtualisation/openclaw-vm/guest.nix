# OpenClaw MicroVM Guest Configuration
# Simple microvm that runs openclaw gateway with network access to safemolt
{ config
, pkgs
, lib ? pkgs.lib
, nix-openclaw
, ...
}:
let
  openclaw-pkg = nix-openclaw.packages.${pkgs.system}.openclaw;
in
{
  config = {
    system.stateVersion = "25.11";
    networking.hostName = "openclaw-vm";

    # Network access for safemolt
    networking.useDHCP = true;
    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 18789 ];  # Gateway port
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
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "openclaw";
        WorkingDirectory = "/home/openclaw";
        ExecStartPre = "${openclaw-pkg}/bin/openclaw onboard --non-interactive --accept-risk --mode local || true";
        ExecStart = "${openclaw-pkg}/bin/openclaw gateway";
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
      vcpu = 2;
      mem = 8192;  # 4GB per vCPU

      # User-mode networking with port forwarding
      interfaces = [{
        type = "user";
        id = "eth0";
        mac = "02:00:00:00:00:01";
      }];

      # Forward gateway port to host
      forwardPorts = [{
        from = "host";
        host.port = 18789;
        guest.port = 18789;
      }];

      # Persistent state volume
      volumes = [{
        mountPoint = "/var/lib/openclaw";
        image = "openclaw-state.img";
        size = 256;
      }];

      # Share host configs into the VM
      shares = [
        {
          tag = "safemolt-config";
          source = "/home/minttea/.config/safemolt";
          mountPoint = "/mnt/safemolt-config";
          proto = "9p";
        }
        {
          tag = "openclaw-skills";
          source = "/home/minttea/.openclaw/skills";
          mountPoint = "/mnt/openclaw-skills";
          proto = "9p";
        }
      ];
    };

    # Create directories and symlink shared configs from host
    systemd.tmpfiles.rules = [
      "d /home/openclaw/.openclaw 0755 openclaw users -"
      "d /home/openclaw/.openclaw/workspace 0755 openclaw users -"
      "d /home/openclaw/.config 0755 openclaw users -"
      "L /home/openclaw/.openclaw/skills - - - - /mnt/openclaw-skills"
      "L /home/openclaw/.config/safemolt - - - - /mnt/safemolt-config"
      "f /home/openclaw/.openclaw/workspace/AGENTS.md 0644 openclaw users -"
      "f /home/openclaw/.openclaw/workspace/SOUL.md 0644 openclaw users -"
      "f /home/openclaw/.openclaw/workspace/TOOLS.md 0644 openclaw users -"
    ];
  };
}
