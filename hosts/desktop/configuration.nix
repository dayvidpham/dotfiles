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
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  #########################
  # General system-config

  # Networking
  networking = {
    hostName = "desktop"; # Define your hostname.
    networkmanager.enable = true; # Easiest to use and most distros use this by default.
  };

  # Cross-compile for aarch64
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Set time zone.
  time.timeZone = "America/Vancouver";

  # Enable SSH daemon
  CUSTOM.services.openssh.enable = true;

  #####################################################
  # Package management
  nixpkgs.config.cudaSupport = true;

  ######################################
  # Window manager & GPU
  programs.hyprland.enable = true;
  CUSTOM.programs.hyprlock.enable = true;
  CUSTOM.programs.eww.enable = true;

  # Sway for remote desktop & waypipe
  CUSTOM.programs.sway.enable = true;

  CUSTOM.hardware.nvidia = {
    enable = true;
    proprietaryDrivers.enable = true;
  };
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
  # Gaming
  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.gamemode.enable = true;

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" "gamemode" ];
  };
}
