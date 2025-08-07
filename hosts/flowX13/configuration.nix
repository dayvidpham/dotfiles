# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config
, pkgs
, lib
, ...
}:
let
  inherit (lib)
    mkBefore
    mkDefault
    ;
in
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
  nix.settings.allowed-users = [
    "minttea"
  ];


  ###############################
  # Locally-hosted binary cache settings
  nix.settings.builders = mkBefore [
    "@/etc/nix/machines"
  ];
  nix.settings.substituters = mkBefore [
    "ssh-ng://nix-ssh@desktop.tsnet.vpn.dhpham.com?priority=1"
    "ssh-ng://nix-ssh@desktop?priority=5"
  ];
  nix.settings.trusted-substituters = mkBefore [
    "ssh-ng://nix-ssh@desktop.tsnet.vpn.dhpham.com?priority=1"
    "ssh-ng://nix-ssh@desktop?priority=5"
  ];
  nix.settings.trusted-public-keys = mkBefore [
    "desktop.tsnet.vpn.dhpham.com:8/RG/7HFPqSRRo7IWyGZwwiwgLs1i9FciO2FQEXN7ic="
    "desktop:pvQ4+Av5pSnMWzi+bpe0okmmLPpeubeHyRHnUEYs+10="
  ];

  # useful when the builder has a faster internet connection than yours
  # otherwise clients upload deps to builders
  nix.settings.builders-use-substitutes = true;

  programs.ssh.extraConfig = ''
    Host desktop
        Port 8108
  '';

  nix.buildMachines = [
    {
      # Will be used to call "ssh builder" to connect to the builder machine.
      # The details of the connection (user, port, url etc.)
      # are taken from your "~/.ssh/config" file.
      hostName = "desktop.tsnet.vpn.dhpham.com";
      # CPU architecture of the builder, and the operating system it runs.
      system = "x86_64-linux";
      # ssh-ng is a Nix custom ssh-variant that avoids lots of "trusted-users" settings pain
      protocol = "ssh-ng";

      sshUser = "nix-ssh";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU8xZDIrbGhDemRocnhhTDhxckE1VVc5V0N6SUN5VXBWbHQrZXJCWkZkazEgcm9vdEBkZXNrdG9wCg==";

      # default is 1 but may keep the builder idle in between builds
      maxJobs = 16;
      # how fast is the builder compared to your local machine
      speedFactor = 8;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ]
        ++ [ "nix-command" "flakes" "fetch-closure" ]
      ;
    }
    {
      # Will be used to call "ssh builder" to connect to the builder machine.
      # The details of the connection (user, port, url etc.)
      # are taken from your "~/.ssh/config" file.
      hostName = "desktop";
      # CPU architecture of the builder, and the operating system it runs.
      system = "x86_64-linux";
      # ssh-ng is a Nix custom ssh-variant that avoids lots of "trusted-users" settings pain
      protocol = "ssh-ng";

      sshUser = "nix-ssh";
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU8xZDIrbGhDemRocnhhTDhxckE1VVc5V0N6SUN5VXBWbHQrZXJCWkZkazEgcm9vdEBkZXNrdG9wCg==";

      # default is 1 but may keep the builder idle in between builds
      maxJobs = 16;
      # how fast is the builder compared to your local machine
      speedFactor = 8;
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ]
        ++ [ "nix-command" "flakes" "fetch-closure" ]
      ;
    }
  ];
  # required, otherwise remote buildMachines above aren't used
  nix.distributedBuilds = true;


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
    kernelPackages = pkgs.linuxPackages_6_15;
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
      DHCP = "yes";
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
  CUSTOM.hardware.nvidia.hostName = "flowX13";
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
