# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{ config, lib, pkgs, ... }:
let
  inherit (lib)
    mkOverride
    mkForce
    ;
in
{
  /**
   * nixos-wsl config
   */
  system.stateVersion = "24.05"; # Did you read the comment?
  wsl.enable = true;
  wsl.defaultUser = "minttea";
  wsl.wslConf.network.hostname = "flowX13-wsl";
  wsl.interop.register = true;
  wsl.docker-desktop.enable = true;

  ############
  # Use Windows OpenGL drivers?
  #wsl.useWindowsDriver = true;
  boot.kernelModules = [
    "vgem"
  ];

  networking.hostName = "flowX13-wsl";
  networking.usePredictableInterfaceNames = true;


  ########
  # Apparently most recent commit removed this and broke Wayland
  systemd.services."user-runtime-dir@" = {
    overrideStrategy = "asDropin";
    serviceConfig.ExecStart = [
      "" # unset old value
      "${pkgs.coreutils}/bin/true"
    ];
  };

  #########################
  # Defines sane defaults
  CUSTOM.shared.enable = true;

  # Does WSL support running Sway?
  CUSTOM.programs.sway.enable = true;

  # WSL manages own networking
  services.resolved.enable = mkForce false;
  systemd.network.enable = mkForce false;
  networking.nameservers = mkForce [ ];

  CUSTOM.services.tailscale.enable = true;

  # Set time zone.
  time.timeZone = "America/Vancouver";

  ######################################
  # GPU
  CUSTOM.hardware.nvidia = {
    enable = true;
    proprietaryDrivers.enable = true;
  };

  services.xserver = {
    enable = true;
    xkb.layout = "us";
  };

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "video" ];
  };


  ######################################
  # Cross-compilation
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
}
