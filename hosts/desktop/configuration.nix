# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config
, pkgs
, pkgs-unstable
, home-manager
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
  boot.kernelPackages = pkgs.linuxPackages_6_15;

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

  # Try getting AMD iGPU to work @_@
  # hardware.amdgpu = {
  #   amdvlk.enable = true;
  #   opencl.enable = true;
  #   initrd.enable = true;
  # };

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
