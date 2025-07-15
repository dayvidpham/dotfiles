# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  system.stateVersion = "23.11";
  nix = {
    # NOTE: Nix store gc, optimisation
    gc = {
      automatic = true;
      persistent = true;
      dates = "weekly";
    };
    settings.auto-optimise-store = true;
  };
  nix.settings.extra-allowed-users = [
    "minttea"
  ];


  ###############################
  # Locally-hosted binary cache settings
  nix.settings.builders = pkgs.lib.mkForce [
    "ssh://nix-ssh@desktop"
    "@/etc/nix/machines"
  ];
  nix.settings.trusted-substituters = [
    "ssh://nix-ssh@desktop"
  ];
  nix.settings.extra-trusted-public-keys = [
    "cache.desktop.org:Sds3S8EjsjypNfQQekd7gmHg19PFZwbjR7Dko/r9mfY="
  ];

  nix.buildMachines = [{
    # Will be used to call "ssh builder" to connect to the builder machine.
    # The details of the connection (user, port, url etc.)
    # are taken from your "~/.ssh/config" file.
    hostName = "desktop";
    # CPU architecture of the builder, and the operating system it runs.
    system = "x86_64-linux";
    # Nix custom ssh-variant that avoids lots of "trusted-users" settings pain
    protocol = "ssh-ng";

    sshUser = "nix-ssh";
    publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU8xZDIrbGhDemRocnhhTDhxckE1VVc5V0N6SUN5VXBWbHQrZXJCWkZkazEgcm9vdEBkZXNrdG9wCg==";

    # default is 1 but may keep the builder idle in between builds
    maxJobs = 16;
    # how fast is the builder compared to your local machine
    speedFactor = 8;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ]
      #++ [ "nix-command" "flakes" "fetch-closure" ]
    ;
    mandatoryFeatures = [ ];
  }];
  # required, otherwise remote buildMachines above aren't used
  nix.distributedBuilds = true;
  # optional, useful when the builder has a faster internet connection than yours
  nix.settings = {
    builders-use-substitutes = true;
  };


  #########################
  # Boot loader
  boot = {
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    loader.systemd-boot.extraFiles = {
      "loader/loader.conf" = pkgs.writeText "loader.conf" ''
        timeout 10
        default @saved
        console-mode keep
      '';
    };
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_6_12;
  };

  # ################################
  # General system-config
  CUSTOM.shared.enable = true;
  environment.systemPackages = [ pkgs.ryzenadj ];

  # ################################
  # Desktop
  CUSTOM.programs.niri.enable = true;

  # Networking
  networking = {
    hostName = "flowX13"; # Define your hostname.

    # NOTE: For GrSim
    firewall.allowedUDPPorts = [
      10003
      10020
    ];
  };

  networking.usePredictableInterfaceNames = true;
  CUSTOM.services.tailscale.enable = true;

  # Use systemd-networkd (eth) AND NetworkManager (wifi) AND resolved (dns)
  # systemd-networkd
  systemd.network.enable = true;
  networking.useNetworkd = true;
  systemd.network.wait-online.enable = false;

  systemd.network.networks."99-wired" = {
    matchConfig.Type = "ether";
    networkConfig = {
      Description = "Ethernet iface";
      IPv6PrivacyExtensions = "kernel";
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Keep names, wlans are unmanaged
  systemd.network.links."10-wlan-names" = {
    matchConfig.Type = "wlan";
    linkConfig.NamePolicy = [ "keep" "database" "onboard" "slot" "path" ];
  };
  systemd.network.networks."10-wlan-unmanaged" = {
    matchConfig.Type = "wlan";
    linkConfig.Unmanaged = true;
  };

  # NetworkManager
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = true;
  networking.networkmanager.wifi.macAddress = "stable-ssid";
  networking.networkmanager.unmanaged = [
    "device-type:ether"
    "interface-name:tailscale*"
  ];

  # systemd-resolved
  services.resolved.enable = true;

  systemd.network.networks."50-wlp6s0" = (
    config.CUSTOM.generate.systemd.network {
      matchConfig.Name = "wlp6s0";
      networkConfig = {
        Description = "Wireless 802.11 WiFi iface";
        IPv6PrivacyExtensions = "kernel";
      };
      linkConfig.RequiredForOnline = "no";
    }
  );

  ######################################
  # Virtualisation
  programs.dconf.enable = true; # virt-manager requires dconf to be enabled
  programs.virt-manager = {
    # GUI for controlling QEMU/KVM VMs on libvirtd
    enable = true;
  };
  virtualisation.libvirtd.enable = true;

  CUSTOM.virtualisation.podman.enable = true;

  # Set time zone.
  time.timeZone = "America/Vancouver";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver = {
    enable = true;
    xkb.variant = "";
    xkb.layout = "us";
    videoDrivers = [ "nvidia" "amdgpu" ];
  };

  CUSTOM.hardware.nvidia.enable = true;
  CUSTOM.hardware.nvidia.hostName = "laptop";
  CUSTOM.hardware.nvidia.proprietaryDrivers.enable = true;

  # enables switching between dGPU and iGPU
  services.supergfxd.enable = true;

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    packages = [ pkgs.godot ];
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" "gamemode" ];
  };


}
