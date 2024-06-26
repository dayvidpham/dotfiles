# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  system.stateVersion = "23.11";
  nix = {
    # Enable flakes
    package = pkgs.nixFlakes;
    settings.experimental-features = [ "nix-command" "flakes" ];
  };

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
    kernelPackages = pkgs.linuxPackages_latest;
  };


  #########################
  # General system-config

  # Networking
  networking = {
    hostName = "desktop"; # Define your hostname.
    networkmanager.enable = true;  # Easiest to use and most distros use this by default.
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;


  # Virtualisation
  programs.dconf.enable = true; # virt-manager requires dconf to be enabled
  programs.virt-manager = {
    # GUI for controlling QEMU/KVM VMs on libvirtd
    enable = true;
  };
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true; # Software Trusted Platform Module: virtualized cryptoprocessor
      ovmf = {
        # Open Virtual Machine Firmware: enables UEFI support for VMs
        # Use UEFI over traditional BIOS
        enable = true;
        packages = [ 
          (pkgs.OVMF.override {
            secureBoot = false;
            tpmSupport = true;
          }).fd 
        ];
      };
    };
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
  #hardware.pulseaudio.enable = false;  # Don't explicitly disable???
  services.pipewire = {
    enable = true;
    audio.enable = true;
    wireplumber = {
      enable = true;
      configPackages = [
        (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/10-bluez.conf" ''
          monitor.bluez.properties = {
            bluez5.roles = [ a2dp_sink a2dp_source bap_sink bap_source ]
            bluez5.codecs = [ sbc sbc_xq aac ]
            bluez5.enable-sbc-xq = true
          }
        '')
      ];
    };

    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = false;
    };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  security.rtkit.enable = true;
  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
  services.gnome.gnome-keyring.enable = true;

  #####################################################
  # Package management
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    ######## 
    # HW utils
    hwinfo        # lower-level hardware (cpu/pci/usb) info
    file          # returns device/file type and info
    lshw          # list connected hardware devices
    bluez         # bluetooth
    # disk
    gparted
    polkit_gnome
    # cli
    zip 
    unzip
    # getters
    wget 
    curl
    # greeter
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
  # Window manager & GPU
  programs.sway = {
    enable = true;
  };
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };
  hardware.enableRedistributableFirmware = pkgs.lib.mkDefault true;
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    modesetting.enable = true;
    nvidiaSettings = true;

    powerManagement = {
      enable = true;
    };

    # Open kernel module: this is not the nouveau driver
    open = false; # GTX 10XX gen is unsupported
  };
  services.xserver = {
    enable = true;
    # If commented, will use nouveau drivers
    #videoDrivers = [ "nvidia" ];
    xkb.variant = "";
    xkb.layout = "us";
  };
  programs.xwayland.enable = true;
  xdg.portal = {
    enable = true;
    # xdgOpenUsePortal = true;
    wlr.enable = true;
    config = {
      sway = {
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
          ${pkgs.greetd.tuigreet}/bin/tuigreet --remember-session --remember --time --asterisks --cmd "sway"
        '';
        user = "greeter";
      };
    };
  };
  services.dbus.enable = true;

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" ];
  };
}
