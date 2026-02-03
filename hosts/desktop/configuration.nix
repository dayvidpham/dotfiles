# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config
, pkgs
, pkgs-unstable
, home-manager
, nix-openclaw
, lib ? config.lib
, ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  system.stateVersion = "23.11";

  #########################
  # Defines sane defaults
  CUSTOM.shared.enable = true;

  #########################
  # Boot loader
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  #########################
  # General system-config

  # Networking
  networking = {
    hostName = "desktop"; # Define your hostname.
    usePredictableInterfaceNames = true;
    networkmanager.enable = false; # Easiest to use and most distros use this by default.
    useNetworkd = true;

    # NOTE: For GrSim
    firewall.allowedUDPPorts = [
      10003
      10020
      10300
      10301
      10302
      30011
      30012
    ];
    firewall.allowedTCPPorts = [
      10003
      10020
      10300
      10301
      10302
      30011
      30012
    ];
    firewall.checkReversePath = "loose";
    firewall.logReversePathDrops = true;
    firewall.logRefusedConnections = true;

    firewall.allowPing = false;
  };
  CUSTOM.services.tailscale.enable = true;

  systemd.network.enable = true;
  systemd.network.links."50-eth-wol" = {
    matchConfig = {
      MACAddress = "9c:1e:95:9c:4f:50";
      Type = "ether";
    };
    linkConfig = {
      MACAddressPolicy = "persistent";
      NamePolicy = "kernel database onboard slot path";
      WakeOnLan = "magic";
    };
  };

  systemd.network.networks."50-enp8s0" = (
    config.CUSTOM.generate.systemd.network {
      matchConfig.Name = "enp8s0";
      networkConfig = {
        Description = "eth 2.5 Gbit iface";
      };
      linkConfig.RequiredForOnline = "routable";
    }
  );

  systemd.network.networks."50-enp5s0" = (
    config.CUSTOM.generate.systemd.network {
      matchConfig.Name = "enp5s0";
      networkConfig = {
        Description = "eth 1 Gbit iface, ISP";
      };
      linkConfig.RequiredForOnline = "yes";
    }
  );

  #systemd.network.networks."50-tailscale0" = (
  #  config.CUSTOM.generate.systemd.network {
  #    matchConfig.Name = "tailscale0";
  #    networkConfig = {
  #      Description = "Tailscale VPN";
  #    };
  #    linkConfig.RequiredForOnline = "yes";
  #  }
  #);

  services.resolved.enable = true;

  networking.nftables.enable = true;

  environment.systemPackages = [
    pkgs.wireshark-qt
  ];
  programs.wireshark.enable = true;
  programs.wireshark.dumpcap.enable = true;


  # Cross-compile for aarch64
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Set time zone.
  time.timeZone = "America/Vancouver";

  # Enable SSH daemon
  CUSTOM.services.openssh.enable = true;

  # For non-root gitlab-runner running from systemd user service
  CUSTOM.services.gitlab-runner = {
    enable = true;
    sudoInto.enable = true;
    sudoInto.fromUser = "minttea";
  };

  #####################################################
  # Package management
  nixpkgs.config.cudaSupport = true;

  # Use desktop's /nix/ store as nix cache served over ssh
  nix.sshServe.enable = true;
  nix.sshServe.trusted = true;
  nix.sshServe.write = true;
  nix.sshServe.protocol = "ssh-ng";

  # Remote users allowed to access the store
  nix.sshServe.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHokUTC0zB6bZvqRtXG8GAekzCLjvsSBNXL2Y/tBmyI7 root@flowX13"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFE9Bzi5oGzx9d68d4lVLgo/d1GypUwE7MhAQ7Z32LlR minttea@flowX13"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILbeKlRuPta2IE0KFAMf4ia7NwCSLoqhr6dgJhHpoJed root@hs0"
  ];

  nix.settings.allowed-users = [
    "minttea"
  ];
  nix.settings.secret-key-files = [
    "/etc/nix/desktop-cache-1-private-key.pem"
    "/etc/nix/tsnet-cache-1-private-key.pem"
  ];

  ######################################
  # Window manager & GPU
  #programs.hyprland.enable = false;
  CUSTOM.programs.hyprlock.enable = true;
  CUSTOM.programs.eww.enable = true;

  # Sway for remote desktop & waypipe
  CUSTOM.programs.sway.enable = true;

  # niri, experimental
  CUSTOM.programs.niri.enable = true;

  CUSTOM.hardware.nvidia = {
    enable = true;
    proprietaryDrivers.enable = true;
  };

  services.xserver = {
    enable = true;
    xkb.layout = "us";
    videoDrivers = [ "nvidia" "amdgpu" "modesetting" ];
  };

  ############################
  # Steam

  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.steam.gamescopeSession.args = [
    "--xwayland-count 2"
    "-e"
    "--prefer-output 'DP-5,DP-2'"
    "-W 2560"
    "-H 1440"
    "-r 170"
  ];
  programs.gamescope.enable = true;
  programs.gamescope.capSysNice = true;

  # /Steam
  ############################

  # Virtualisation
  CUSTOM.virtualisation.podman.enable = true;
  CUSTOM.virtualisation.libvirtd.enable = true;
  CUSTOM.virtualisation.llm-sandbox.enable = true;

  # OpenClaw AI Assistant (secure containerized setup)
  # NOTE: Disabled - using microVM instead (openclaw-vm)
  CUSTOM.virtualisation.openclaw = {
    enable = false;

    # Container configuration
    container.gatewayPackage = nix-openclaw.packages.${pkgs.system}.openclaw-gateway;

    # sops-nix secrets configuration
    secrets = {
      enable = true;
      sopsFile = ../../secrets/openclaw/secrets.yaml;
      ageKeyFile = "/var/lib/sops-nix/keys.txt";
    };

    # Network security (strict allowlist)
    network = {
      enable = true;
      strictFirewall = true;
      allowlist = {
        domains = [ "api.anthropic.com" ];
        allowDns = true;
      };
    };

    # Inter-instance communication bridge
    bridge = {
      enable = true;
      port = 18800;
      rateLimit = 60;
      maxDelegationDepth = 5;
    };

    # Instance configurations
    instances = {
      alpha = {
        enable = false;
        ports = {
          webchat = 3000;
          gateway = 18789;
        };
        workspace = {
          path = "/var/lib/openclaw/alpha/workspace";
          configPath = "/var/lib/openclaw/alpha/config";
        };
        resources = {
          memoryLimit = "4g";
          cpuLimit = "2.0";
        };
        openclaw = {
          agentName = "Alpha";
          sandboxMode = "all";
        };
      };

      beta = {
        enable = false;
        ports = {
          webchat = 3001;
          gateway = 18790;
        };
        workspace = {
          path = "/var/lib/openclaw/beta/workspace";
          configPath = "/var/lib/openclaw/beta/config";
        };
        resources = {
          memoryLimit = "4g";
          cpuLimit = "2.0";
        };
        openclaw = {
          agentName = "Beta";
          sandboxMode = "all";
        };
      };
    };
  };

  # OpenClaw VM - microVM-based isolation for gateway
  CUSTOM.virtualisation.openclaw-vm = {
    enable = true;
    dangerousDevMode.enable = true; # No auto-login, no guest agent
    useVirtiofs = true; # Fast rebuilds via host /nix/store
    gatewayPort = 18789;
    memory = 8192; # 4GB per vCPU
    vcpu = 2;
    secrets = {
      enable = true;
      sopsFile = ../../secrets/openclaw/secrets.yaml;
    };
    # Caddy reverse proxy disabled - using Tailscale Serve instead
    # Tailscale Serve provides HTTPS + identity-based auth via tailnet
    caddy.enable = false;
    # Tailscale for remote access via tailnet (using Headscale)
    tailscale = {
      enable = true;
      hostname = "openclaw-vm";
      loginServer = "https://hs0.vpn.dhpham.com";
      exitNode = null; # Set after initial auth via post-connect service
      sshAuthorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFE9Bzi5oGzx9d68d4lVLgo/d1GypUwE7MhAQ7Z32LlR minttea@flowX13"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbEq1/i8sCEuKZV5xFr+S5T12u54kEyqYHqD2/Xu2kX minttea@desktop"
      ];
    };
  };

  # Configure sops-nix for system-level secrets (used by openclaw-vm)
  sops.age.keyFile = "/var/lib/sops-nix/keys.txt";

  # Try getting AMD iGPU to work @_@
  # hardware.amdgpu = {
  #   amdvlk.enable = true;
  #   opencl.enable = true;
  #   initrd.enable = true;
  # };

  # Persistent tmux server (survives DE/WM/session closures)
  CUSTOM.programs.tmux.server = {
    enable = true;
    user = "minttea";
  };

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [
      "networkmanager"
      "wheel"
      "libvirtd"
      "vmusers"
      "video"
      "gamemode"
      "gitlab-runner"
      "wireshark"
    ];
    subUidRanges = [
      {
        startUid = 100000;
        count = 165535;
      }
    ];
    subGidRanges = [
      {
        startGid = 100000;
        count = 165535;
      }
    ];
  };

}
