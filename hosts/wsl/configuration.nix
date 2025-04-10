# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL

{ config, lib, pkgs, ... }:

{
  /**
   * nixos-wsl config
   */
  system.stateVersion = "24.05"; # Did you read the comment?
  wsl.enable = true;
  wsl.defaultUser = "minttea";
  wsl.wslConf.network.hostname = "wsl";
  wsl.interop.register = true;
  networking.hostName = "wsl";

  #########################
  # Defines sane defaults
  CUSTOM.shared.enable = true;
  services.resolved.enable = false;
  systemd.network.enable = false;

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
  #boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
}
