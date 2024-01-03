# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  system.stateVersion = "23.05";
  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

  boot = {
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_latest;
  }; 
  virtualisation.vmware.guest.enable = true;


  # ################################
  # General system-config

  # Networking
  networking = {
    hostName = "nixos"; # Define your hostname.
    networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  };

  # Set time zone.
  time.timeZone = "America/Vancouver";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Setup tty and fonts
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      (nerdfonts.override { fonts = [ "iA-Writer" ]; })
    ];
  };
  console = {
    keyMap = "us";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  security.rtkit.enable = true;
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  #####################################################
  # Package management
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    hwinfo
    file
    wget curl
    greetd.tuigreet
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

  ######################################
  # Window manager
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  hardware.enableRedistributableFirmware = pkgs.lib.mkDefault true;
  services.xserver = {
    enable = true;
    xkb.layout = "us";
    videoDrivers = [ "vmware" ];
  };
  programs.xwayland.enable = true;
  xdg.portal = {
    enable = true;
    # xdgOpenUsePortal = true;
    wlr.enable = true;
    config = {
      dwl = {
        default = [ "wlr" "gtk" ];
      };
      common = {
        default = [ "gtk" ];
      };
    };
    configPackages = with pkgs; [
      xdg-desktop-portal-wlr
      xdg-desktop-portal-gtk
    ];
  };

  services.logind.extraConfig = ''
    # Don't shutdown when power button is short-pressed
    HandlePowerKey=ignore
  '';

  # Display manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = ''
          ${pkgs.greetd.tuigreet}/bin/tuigreet --remember-session --remember --time --asterisks --cmd "dwl -s 'kanshi& alacritty -e ranger' > /tmp/dwltags"
        '';
        user = "greeter";
      };
    };
  };
  services.dbus.enable = true;
  # nixpkgs.overlays = [
  #   (final: prev: {
  #     dwl = prev.dwl.override { conf = ./dwl-config.h; };
  #   })
  # ];

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.dhpham = {
    isNormalUser = true;
    description = "dhpham";
    extraGroups = [ "networkmanager" "wheel" ];
  };
}
