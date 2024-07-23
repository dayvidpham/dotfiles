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

  /**
   * nixos-wsl config
   */
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

  #####################################################
  # Package management
  nixpkgs.config.allowUnfree = true;
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

  CUSTOM.hardware.nvidia = {
    enable = true;
    proprietaryDrivers.enable = true;
  };
  # Try getting AMD iGPU to work @_@
  hardware.amdgpu = {
    amdvlk.enable = true;
    opencl.enable = true;
    initrd.enable = true;
  };

  services.xserver = {
    enable = true;
    xkb.layout = "us";
  };

  # NOTE: Not sure why I set this option originally
  hardware.enableRedistributableFirmware = pkgs.lib.mkDefault true;

  ######################################
  # Greeter
  services.logind.extraConfig = ''
    # Don't shutdown when power button is short-pressed
    HandlePowerKey=ignore
  '';

  # NOTE: For GTK config, e.g. cursor configuration
  services.dbus.enable = true;

  ######################################
  # Some user setup: Most user-stuff will be in home-manager
  users.users.minttea = {
    isNormalUser = true;
    description = "the guy";
    extraGroups = [ "networkmanager" "wheel" "video" ];
  };
}
