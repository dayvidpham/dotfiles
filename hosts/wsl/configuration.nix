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

  nix = {
    # NOTE: Enable Flakes
    package = pkgs.nixVersions.git; # enable experimental multithreaded eval
    settings.experimental-features = [ "nix-command" "flakes" ];

    # NOTE: Nix store gc, optimisation
    gc = {
      automatic = true;
      persistent = false;
      dates = "7 days";
    };
    settings.auto-optimise-store = true;
  };
}
