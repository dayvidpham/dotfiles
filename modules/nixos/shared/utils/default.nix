{ config
, pkgs
, pkgs-unstable
, lib ? config.lib
, ...
}:
lib.mkIf (config.CUSTOM.shared.enable) {
  programs.command-not-found.enable = false;

  environment.systemPackages = (with pkgs; [
    # Nix utils
    nix-output-monitor # more informative nix build outputs
    nix-tree # interactive closure explorer
    nvd # closure differ
    nix-index # offline index of all files in nixpkgs, can search for files
    nix-fast-build # multithreaded nix eval? for CI? can I use for nixos-rebuild?
    manix # settings searcher

    # CLI/system tools
    cyme # lsusb alternative, better UI
    hwinfo # lower-level hardware (cpu/pci/usb) info
    file # returns device/file type and info
    lshw # list connected hardware devices
    btop # modern top/htop alternative
    ripgrep # modern grep
    ripgrep-all # fast search on cli; rg and rga
    ast-grep # structured search
    dust # du but rusty
    git
    git-lfs

    # Development runtimes/tools
    python3
    uv # fast Python package installer
    bun # fast JavaScript runtime

    # Secrets management
    age # modern encryption tool
    sops # secrets operations

    # Networking
    lsof
    net-tools
    socat # bidirectional socket relay (for VM console access, port forwarding, etc.)
    ethtool # NIC config
    dig # DNS lookups

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
  ])
  ++ (with pkgs-unstable; [
    nix-search # offline nixpkgs package search, fuck default nix search
  ]);

  programs.nix-index.enable = true;
  programs.nix-index.enableZshIntegration = true;

  programs.bat.enable = true;
  programs.bat.extraPackages =
    let
      isPackage = lib.types.package.check;
      batPkgAttrs = lib.filterAttrs (key: val: isPackage val) pkgs.bat-extras;
      batPkgs = lib.mapAttrsToList (key: val: val) batPkgAttrs;
    in
    batPkgs;
}
