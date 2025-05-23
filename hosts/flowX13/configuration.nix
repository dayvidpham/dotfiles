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
    "ssh://desktop"
    "@/etc/nix/machines"
  ];
  nix.settings.extra-trusted-substituters = [
    "ssh://desktop"
  ];
  nix.settings.extra-trusted-public-keys = [
    "cache.desktop.org:Sds3S8EjsjypNfQQekd7gmHg19PFZwbjR7Dko/r9mfY="
  ];


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

  # ################################
  # Desktop
  CUSTOM.programs.niri.enable = true;

  # Networking
  networking = {
    hostName = "flowX13"; # Define your hostname.
    networkmanager.enable = true; # Easiest to use and most distros use this by default.

    # NOTE: For GrSim
    firewall.allowedUDPPorts = [
      10003
      10020
    ];
    wireguard = {
      enable = true;
      useNetworkd = false;
    };
  };
  services.resolved.enable = false;

  systemd.network.networks."50-wlp6s0" = (
    config.CUSTOM.generate.systemd.network {
      matchConfig.Name = "wlp6s0";
      networkConfig = {
        Description = "Wireless 802.11 WiFi iface";
      };
      linkConfig.RequiredForOnline = "routable";
    }
  );

  # Virtualisation
  programs.dconf.enable = true; # virt-manager requires dconf to be enabled
  programs.virt-manager = {
    # GUI for controlling QEMU/KVM VMs on libvirtd
    enable = true;
  };

  # Virtualisation
  CUSTOM.podman.enable = true;

  # Set time zone.
  time.timeZone = "America/Vancouver";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver = {
    enable = true;
    xkb.variant = "";
    xkb.layout = "us";
    videoDrivers = [ "nouveau" "amdgpu" ];
  };

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" "gamemode" ];
  };
}
