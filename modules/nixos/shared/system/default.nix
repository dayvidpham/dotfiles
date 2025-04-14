{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    isAttrs# To check if a value is an attribute set
    isList# To check if a value is a list
    isFunction# To check if a value is a function
    ;

  # Condition function: Returns true only for non-nested types
  # We want to apply mkDefault ONLY IF the value is NOT an attrset, NOT a list, and NOT a function.
  shouldMakeDefault = value: !(isAttrs value || isList value || isFunction value);

  mkDefaults = (defset:
    lib.mapAttrsRecursiveCond shouldMakeDefault (_: value: mkDefault value) defset
  );
in
mkIf (config.CUSTOM.shared.enable) {
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
  };

  #########################
  # General system-config
  nix = {
    gc = {
      automatic = true;
      persistent = true;
      dates = "weekly";
    };
    settings.auto-optimise-store = true;
  };

  documentation.enable = true;
  documentation.man.generateCaches = config.documentation.man.enable;

  ######################################
  # Allow firmware with unfree licenses
  hardware.enableAllFirmware = true;
  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Setup tty and fonts
  CUSTOM.fonts.enable = true;
  console = {
    keyMap = "us";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;
  # Select internationalisation properties.
  i18n.defaultLocale = "en_CA.UTF-8";

  # Enable sound.
  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      configPackages = [
        # Disable hands-free mode
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
  # Package management, packages
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [
    # greeter
    pkgs.greetd.tuigreet
    # remote wayland
    pkgs-unstable.waypipe
  ];

  CUSTOM.programs.git.enable = true;
  CUSTOM.programs.zsh.enable = true;
  # For OBS and screen sharing/recording
  CUSTOM.v4l2loopback.enable = true;

  # For AppImage compatibility
  programs.appimage.enable = true;
  programs.appimage.binfmt = true;

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

  ##############
  # Networking
  #
  # man systemd.network 
  systemd.network.enable = true;

  # returns an attrset
  CUSTOM.generate.systemd.network = override: lib.mkMerge [
    override
    {
      # Default
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      dhcpV4Config = {
        UseDNS = false;
      };
      dhcpV6Config = {
        UseDNS = false;
      };
      ipv6AcceptRAConfig = {
        UseDNS = false;
      };
    }
  ];


  # man resolved.conf
  services.resolved.enable = true;
  services.resolved.dnssec = "allow-downgrade";
  services.resolved.dnsovertls = "opportunistic";
  services.resolved.domains = [
    "~."
  ];

  networking.nameservers = [
    #"194.242.2.4#base.dns.mullvad.net."
    "9.9.9.9#dns.quad9.net."
    #"2a07:e340::4#base.dns.mullvad.net."
    "2620:fe::fe#dns.quad9.net."
  ];

  services.resolved.fallbackDns = [
    "1.1.1.1#one.one.one.one."
  ]
  ++
  (lib.optional
    (config.networking.defaultGateway != null)
    config.networking.defaultGateway)
  ;


  # Virtualisation
  # TODO: Split this into separate module
  programs.dconf.enable = true; # virt-manager requires dconf to be enabled
  programs.virt-manager = {
    # GUI for controlling QEMU/KVM VMs on libvirtd
    enable = true;
  };
  virtualisation.libvirtd = {
    enable = false;
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
}
