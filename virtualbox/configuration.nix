# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the systemd-boot EFI boot loader.
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nixpkgs.config.allowUnfree = true;
  system.copySystemConfiguration = true;
  system.stateVersion = "23.05";

  networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "America/Vancouver";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  fonts = {
    enableDefaultFonts = true;
    fonts = with pkgs; [
      (nerdfonts.override { fonts = [ "iA-Writer" ]; })
    ];
  };
  console = {
    font = "arm8";
    keyMap = "us";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.dhpham = {
    isNormalUser = true;
    description = "dhpham";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
      firefox
      tree
    ];
  };

  # List packages installed in system profile. To search, run:
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    alacritty
  ];
  programs.vim.defaultEditor = true;
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      user.name = "dayvidpham";
      user.email = "dayvidpham@gmail.com";
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Window manager
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };
}
