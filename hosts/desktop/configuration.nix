# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config
, pkgs
, pkgs-unstable
, home-manager
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
    networkmanager.enable = true; # Easiest to use and most distros use this by default.

    # NOTE: For GrSim
    firewall.allowedUDPPorts = [
      10003
      10020
    ];
    firewall.allowPing = true;
    wireguard = {
      enable = true;
      useNetworkd = true;
    };
  };
  CUSTOM.services.tailscale.enable = true;

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
    networking.nat.externalInterface = "enp5s0";
  };

  #####################################################
  # Package management
  nixpkgs.config.cudaSupport = true;

  # Use desktop's /nix/ store as nix cache served over ssh
  nix.sshServe.enable = true;
  nix.sshServe.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFE9Bzi5oGzx9d68d4lVLgo/d1GypUwE7MhAQ7Z32LlR minttea@flowX13"
  ];

  nix.settings.extra-allowed-users = [
    "minttea"
  ];
  nix.settings.extra-trusted-users = [
    "nix-ssh"
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

  # Try getting AMD iGPU to work @_@
  # hardware.amdgpu = {
  #   amdvlk.enable = true;
  #   opencl.enable = true;
  #   initrd.enable = true;
  # };

  services.xserver = {
    enable = true;
    xkb.layout = "us";
    videoDrivers = [ "nvidia" "amdgpu" "modesetting" ];
  };

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" "gamemode" "gitlab-runner" "wireshark" ];
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
