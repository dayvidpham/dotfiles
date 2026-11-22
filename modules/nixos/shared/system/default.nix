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

  # Keygrips for primary GPG key 1DB15D3B97FF019A ([SC] signing + [E] encryption
  # subkey used by pass-secret-service).
  gpgKeygrips = [
    "E2101ABFD3D26D46D0832434AE7BB4D1521DE24D"
    "B12AB1EB03B8F5D3E7F937DC29870B2B1C9E3700"
  ];
  gpgSecretPath = "/run/secrets/gpg/passphrase.scrypt";

  # PAM auth hook (pam_exec expose_authtok): decrypts the scrypt-encrypted GPG
  # passphrase using the Linux login password on stdin and presets both keygrips
  # into gpg-agent. Handles both greetd (UID 0, also called for PAM_USER=greeter)
  # and swaylock (UID 1000). Never puts either password in argv or environ.
  gpgPamUnlock = pkgs.writeShellScript "gpg-pam-unlock" ''
    [ "''${PAM_USER:-}" = "minttea" ] || exit 0
    [ -r "${gpgSecretPath}" ] || exit 0

    IFS= read -r -d "" login_pass || true
    [ -n "$login_pass" ] || exit 0

    (
      umask 077
      gpg_pass="$(printf '%s\n' "$login_pass" | ${pkgs.scrypt}/bin/scrypt dec -P "${gpgSecretPath}" 2>/dev/null || true)"
      [ -n "$gpg_pass" ] || exit 0

      if [ "$(${pkgs.coreutils}/bin/id -u)" -eq 0 ]; then
        printf '%s\n' "$gpg_pass" | ${pkgs.util-linux}/bin/runuser -u minttea -- ${pkgs.bash}/bin/bash -c '
          IFS= read -r pass || exit 0
          uid="$(${pkgs.coreutils}/bin/id -u)"
          export HOME="/home/minttea" XDG_RUNTIME_DIR="/run/user/$uid"
          for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
            [ -d "$XDG_RUNTIME_DIR" ] && break
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
          for grip in ${lib.concatStringsSep " " gpgKeygrips}; do
            printf "%s\n" "$pass" | ${pkgs.gnupg}/libexec/gpg-preset-passphrase --preset "$grip"
          done
        '
      else
        uid="$(${pkgs.coreutils}/bin/id -u)"
        export HOME="/home/minttea" XDG_RUNTIME_DIR="/run/user/$uid"
        ${pkgs.gnupg}/bin/gpgconf --launch gpg-agent
        for grip in ${lib.concatStringsSep " " gpgKeygrips}; do
          printf '%s\n' "$gpg_pass" | ${pkgs.gnupg}/libexec/gpg-preset-passphrase --preset "$grip"
        done
      fi
    ) </dev/null >/dev/null 2>&1 &
    exit 0
  '';

  # Interactive CLI helper to preset both GPG keygrips on demand (e.g. over SSH
  # after a headless reboot or after nixos-rebuild reloads gpg-agent).
  gpgUnlock = pkgs.writeShellApplication {
    name = "gpg-unlock";
    runtimeInputs = [ pkgs.scrypt pkgs.gnupg pkgs.coreutils ];
    text = ''
      set -euo pipefail
      if [ ! -r "${gpgSecretPath}" ]; then
        echo "gpg-unlock: ${gpgSecretPath} not found" >&2
        exit 1
      fi
      gpg_pass="$(scrypt dec "${gpgSecretPath}")"
      gpgconf --launch gpg-agent
      for grip in ${lib.concatStringsSep " " gpgKeygrips}; do
        printf '%s\n' "$gpg_pass" | ${pkgs.gnupg}/libexec/gpg-preset-passphrase --preset "$grip"
      done
      echo "gpg-unlock: preset ${toString (builtins.length gpgKeygrips)} keygrips into gpg-agent"
    '';
  };
in
{
  imports = [
    ./sfuvpn.nix
  ];


  config = mkIf (config.CUSTOM.shared.enable) {
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
    documentation.man.cache.enable = config.documentation.man.enable;

    ######################################
    # Allow firmware with unfree licenses
    hardware.enableAllFirmware = true;

    # Enable hardware accelerated graphics
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

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
    security.polkit.enable = true;
    programs.mtr.enable = true;
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      # Qt-first pinentry with tmux-popup fallback for TUI panes and tty-less
      # Secret Service / ssh-agent requests. See packages/pinentry-tmux.
      # pkgs-unstable so the popup's tmux client matches the persistent
      # server's and home-manager's tmux.
      pinentryPackage = pkgs-unstable.callPackage ../../../../packages/pinentry-tmux { };
      # Configured here (/etc/gnupg/gpg-agent.conf) rather than in Home Manager
      # (~/.gnupg/gpg-agent.conf), because a user gpg-agent.conf shadows the
      # system one and would drop pinentry-program.
      # - no-allow-external-cache prevents pinentry from calling Secret Service
      #   (which is backed by pass-secret-service -> gpg-agent -> deadlock).
      # - allow-preset-passphrase lets PAM (greetd/swaylock) and gpg-unlock
      #   preset keygrips into gpg-agent's in-memory cache.
      settings = {
        no-allow-external-cache = "";
        allow-preset-passphrase = "";
        default-cache-ttl = "86400";
        max-cache-ttl = "86400";
      };
    };

    # Unlock gpg-agent (and therefore pass-secret-service) automatically on
    # greetd login and swaylock unlock via the scrypt-encrypted passphrase.
    security.pam.services.greetd.rules.auth.gpg-pam-unlock = {
      order = config.security.pam.services.greetd.rules.auth.unix.order + 100;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = [ "expose_authtok" "quiet" "${gpgPamUnlock}" ];
    };
    security.pam.services.swaylock.rules.auth.gpg-pam-unlock = {
      order = config.security.pam.services.swaylock.rules.auth.unix.order + 100;
      control = "optional";
      modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
      args = [ "expose_authtok" "quiet" "${gpgPamUnlock}" ];
    };

    #####################################################
    # Package management, packages
    nixpkgs.config.allowUnfree = true;
    services.flatpak.enable = true;
    xdg.portal.enable = true;
    xdg.portal.xdgOpenUsePortal = false;

    environment.sessionVariables = {
      BROWSER = "${pkgs.firefox-bin}/bin/firefox";
      DEFAULT_BROWSER = "${pkgs.firefox-bin}/bin/firefox";
    };

    environment.systemPackages = [
      # greeter
      pkgs.tuigreet
      # On-demand GPG / pass-secret-service unlock helper (SSH / post-rebuild)
      gpgUnlock
      pkgs.scrypt
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
    services.logind.settings.Login = {
      # Don't shutdown when power button is short-pressed
      HandlePowerKey = "ignore";
    };

    # Display manager
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = ''
            ${pkgs.tuigreet}/bin/tuigreet --remember-session --remember --time --asterisks --cmd "niri-session"
          '';
          user = "greeter";
        };
      };
    };
    # NOTE: For GTK config, e.g. cursor configuration
    services.dbus.enable = true;
    services.dbus.implementation = "broker";

    # Terminal multiplexer
    programs.screen.enable = lib.mkDefault true;
    programs.xwayland.enable = true;

    ##############
    # Networking

    # man systemd.network 
    systemd.network.enable = lib.mkDefault false;
    networking.usePredictableInterfaceNames = lib.mkDefault true;

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
          UseDNS = true;
        };
        dhcpV6Config = {
          UseDNS = true;
        };
        ipv6AcceptRAConfig = {
          UseDNS = true;
        };
      }
    ];


    # man resolved.conf
    services.resolved.enable = lib.mkDefault false;
    services.resolved.settings.Resolve.DNSSEC = lib.mkDefault "allow-downgrade";
    services.resolved.settings.Resolve.DNSOverTLS = lib.mkDefault "opportunistic";
    services.resolved.settings.Resolve.Domains = [
      "~."
    ];

    networking.nameservers = [
      #"194.242.2.4#base.dns.mullvad.net."
      "9.9.9.9#dns.quad9.net."
      #"2a07:e340::4#base.dns.mullvad.net."
      "2620:fe::fe#dns.quad9.net."
    ];

    services.resolved.settings.Resolve.FallbackDNS = [
      "1.1.1.1#one.one.one.one."
    ]
    ++
    (lib.optional
      (config.networking.defaultGateway != null)
      config.networking.defaultGateway)
    ;
  };
}
