# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ config
, pkgs
, home-manager
, ...
}:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  system.stateVersion = "23.11";
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

  #########################
  # Boot loader
  boot = {
    # Use the systemd-boot EFI boot loader.
    loader.systemd-boot.enable = true;
    #loader.systemd-boot.extraFiles = {
    #  "loader/loader.conf" = pkgs.writeText "loader.conf" ''
    #      timeout 10
    #      default @saved
    #      console-mode keep
    #    '';
    #};

    loader.efi.canTouchEfiVariables = true;
    kernelPackages = pkgs.linuxPackages_6_6;
  };

  # For OBS and screen sharing/recording
  CUSTOM.v4l2loopback.enable = true;

  #########################
  # General system-config

  # Networking
  networking = {
    hostName = "desktop"; # Define your hostname.
    networkmanager.enable = true; # Easiest to use and most distros use this by default.
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
      # swtpm.enable = true; # Software Trusted Platform Module: virtualized cryptoprocessor
      # ovmf = {
      #   # Open Virtual Machine Firmware: enables UEFI support for VMs
      #   # Use UEFI over traditional BIOS
      #   enable = true;
      #   # packages = [ 
      #   #   (pkgs.OVMF.override {
      #   #     secureBoot = false;
      #   #     tpmSupport = true;
      #   #   }).fd 
      #   # ];
      # };
    };
  };
  # Cross-compile for aarch64
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Set time zone.
  time.timeZone = "America/Vancouver";
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Setup tty and fonts
  CUSTOM.fonts.enable = true;
  console = {
    keyMap = "us";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  #hardware.pulseaudio.enable = false; # Don't explicitly disable???
  services.pipewire = {
    enable = true;
    audio.enable = true;

    pulse.enable = true;

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
  CUSTOM.services.openssh.enable = true;

  #####################################################
  # Package management
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.cudaSupport = true;
  environment.systemPackages = with pkgs; [
    ######## 
    # HW utils
    hwinfo # lower-level hardware (cpu/pci/usb) info
    file # returns device/file type and info
    lshw # list connected hardware devices
    bluez # bluetooth
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
    # remote wayland
    waypipe
    # Nix utils
    nix-output-monitor # more informative nix build outputs
    nix-tree # interactive closure explorer
    nvd # closure differ
    nix-index
  ];

  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      user.name = "dayvidpham";
      user.email = "dayvidpham@gmail.com";
    };
  };

  CUSTOM.programs.zsh.enable = true;

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
  };

  # NOTE: Not sure why I set this option originally
  hardware.enableRedistributableFirmware = pkgs.lib.mkDefault true;


  ######################################
  # Gaming
  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.gamemode.enable = true;

  ######################################
  # Greeter
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
          ${pkgs.greetd.tuigreet}/bin/tuigreet --remember-session --remember --time --asterisks --cmd "Hyprland"
        '';
        user = "greeter";
      };
    };
  };
  # NOTE: For GTK config, e.g. cursor configuration
  services.dbus.enable = true;

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "video" "gamemode" ];
  };
}
