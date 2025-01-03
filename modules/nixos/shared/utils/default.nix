{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}:

{
  programs.command-not-found.enable = false;
  #imports = [
  #  ./nix
  #  ./cli
  #];
  environment.systemPackages = with pkgs; [
    # Nix utils
    nix-output-monitor # more informative nix build outputs
    nix-tree # interactive closure explorer
    nvd # closure differ
    nix-index # offline index of all files in nixpkgs, can search for files
    nix-search # offline nixpkgs package search, fuck default nix search
    nix-fast-build # multithreaded nix eval? for CI? can I use for nixos-rebuild?

    # CLI/system tools
    cyme # lsusb alternative, better UI
    hwinfo # lower-level hardware (cpu/pci/usb) info
    file # returns device/file type and info
    lshw # list connected hardware devices
    # compression stuff
    zip
    unzip
    unrar
    # disk
    gparted # GUI disk partitioning
    polkit_gnome
    # getters
    wget
    curl
  ];

  programs.nix-index.enable = true;
  programs.nix-index.enableZshIntegration = true;
}
