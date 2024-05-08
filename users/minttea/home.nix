{ 
  config
  , pkgs
  , nixvim
  , ... 
}:
let
  # maybe this stuff should be defined in Flake and passed to users
  rstudio-env = pkgs.rstudioWrapper.override { 
    packages = with pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
      reticulate
    ];
  };
  texlive-env = (pkgs.texlive.combine {
    inherit (pkgs.texlive) scheme-full float;
  });
  run-cwd = with pkgs; callPackage ../../programs/run-cwd.nix {
    inherit writeShellApplication runtimeShell sway jq;
  };
  scythe = with pkgs; callPackage ../../programs/scythe.nix {
    inherit writeShellApplication runtimeShell grim slurp dmenu swappy;
    wl-clipboard = wl-clipboard-rs;
    output-dir = "$HOME/Pictures/scythe";
  };
in rec {
  imports = [ 
    # nixvim.homeManagerModules.nixvim
    ../../programs/neovim
  ];
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "minttea";
  home.homeDirectory = "/home/minttea";
  home.stateVersion = "23.11"; # Please read the comment before changing.
  home.pointerCursor = {
    gtk.enable = true;
    name = "Bibata-Modern-Classic";
    size = 24;
    package = pkgs.bibata-cursors;
  };
  gtk = {
    enable = true;
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      size = 24;
      package = pkgs.bibata-cursors;
    };
    theme = {
      name = "Dracula";
      package = pkgs.dracula-theme;
    };
  };

  # Env vars
  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS     = "1";        # Stop cursor from disappearing on NVIDIA GPU
    NIXOS_OZONE_WL              = "1";        # Tell electron apps to use Wayland
    MOZ_ENABLE_WAYLAND          = "1";        # Run Firefox on Wayland
    BEMENU_BACKEND              = "wayland";
    GDK_BACKEND                 = "wayland";
    XDG_CURRENT_DESKTOP         = "sway";
  };

  # Virtualisation
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };

  #####################
  # Graphics

  # Sway config
  programs.waybar = {
    enable = true;
    settings = [{
      height = 30;
      layer = "bottom";
      position = "top";
      tray = { spacing = 10; };
      modules-center = [ "sway/window" ];
      modules-left = [ "sway/workspaces" "sway/mode" ];
      modules-right = [
        "custom/pipewire"
        "network"
        "cpu"
        "memory"
        "temperature"
        "battery"
        "clock"
        "tray"
      ];
      battery = {
        format = "{capacity}% {icon}";
        format-alt = "{time} {icon}";
        format-charging = "{capacity}% ";
        format-icons = [ "" "" "" "" "" ];
        format-plugged = "{capacity}% ";
        states = {
          critical = 15;
          warning = 30;
        };
      };
      clock = {
        format-alt = "{:%Y-%m-%d}";
        tooltip-format = "{:%Y-%m-%d | %H:%M}";
      };
      cpu = {
        format = "{usage}% ";
        tooltip = false;
      };
      memory = { format = "{}% "; };
      network = {
        interval = 1;
        format-alt = "{ifname}: {ipaddr}/{cidr}";
        format-disconnected = "Disconnected ⚠";
        format-ethernet = "{ifname}: {ipaddr}/{cidr}   up: {bandwidthUpBits} down: {bandwidthDownBits}";
        format-linked = "{ifname} (No IP) ";
        format-wifi = "{essid} ({signalStrength}%) ";
      };
      "custom/pipewire" = {
        return-type = "json";
        signal = 8;
        interval = "once";
        exec = "pw-volume status";
        format = "{icon}";
        on-click = "qpwgraph";
        format-icons = {
          mute = "";
          default = [ "" "" "" "" ];
          headphones = "";
          headset = "";
        };
        # format = "{volume}% {icon} {format_source}";
        # format-bluetooth = "{volume}% {icon} {format_source}";
        # format-bluetooth-muted = " {icon} {format_source}";
        # format-icons = {
        #   car = "";
        #   # mute = "";
        #   default = [ "" "" "" "" ];
        #   # default = [ "" "" "" ];
        #   handsfree = "";
        #   headphones = "";
        #   headset = "";
        #   phone = "";
        #   portable = "";
        # };
        # format-muted = " {format_source}";
        # format-source = "{volume}% ";
        # format-source-muted = "";
      };
      "sway/mode" = { format = ''<span style="italic">{}</span>''; };
      temperature = {
        critical-threshold = 80;
        format = "{temperatureC}°C {icon}";
        format-icons = [ "" "" "" ];
      };
    }];
  };
  wayland.windowManager.sway = let
    modifier = "Mod1";
    terminal = "${pkgs.alacritty}/bin/alacritty";
  in {
    enable = true;
    config = {
      terminal = terminal;
      output = {
        "eDP-1" = {
          mode = "1920x1200@119.90Hz";
          scale = "1.25";
        };
        # 3 monitor setup: |V|[ H ]|V|
        "DP-6" = {
          # left
          mode = "2560x1440@169.831Hz";
          scale = "1.5";
          position = "0,0";
          transform = "90";
        };
        "DP-5" = {
          # center
          mode = "2560x1440@169.831Hz";
          scale = "1.5";
          position = "960,300";
        };
        "DP-4" = {
          # right
          mode = "2560x1440@169.831Hz";
          scale = "1.5";
          position = "2666,0";
          transform = "90";
        };
      };
      bars = [
        {
          command = "${pkgs.waybar}/bin/waybar";
        }
      ];
      input = {
        "Logitech G Pro" = {
          accel_profile = "flat";
          pointer_accel = "0.05";
        };
        "type:touchpad" = { 
          tap = "enabled";
          accel_profile = "flat";
          pointer_accel = "0.25";
          scroll_factor = "0.25";
        };
        "*" = {
          accel_profile = "flat";
          tap = "enabled";
          natural_scroll = "false";
        };
      };
      modifier = modifier;
      keybindings = pkgs.lib.mkOptionDefault {
        "${modifier}+Return" = "exec 'run-cwd ${terminal}'";
        "${modifier}+Shift+Return" = "exec 'run-cwd ${terminal} -e ranger'";
        XF86AudioRaiseVolume = "exec 'pw-volume change +2.5%; pkill -RTMIN+8 waybar'";
        XF86AudioLowerVolume = "exec 'pw-volume change -2.5%; pkill -RTMIN+8 waybar'";
        XF86AudioMute = "exec 'pw-volume mute toggle; pkill -RTMIN+8 waybar'";
      };
    };
    extraConfig = ''
        exec ${pkgs.polkit_gnome.outPath}/libexec/polkit-gnome-authentication-agent-1
    '';
  };

  # General package stuff
  home.packages = with pkgs; [
    # Wayland stuff
    bemenu        # launcher menu
    wdisplays     # gui for display settings
    wl-clipboard-rs # Rust CLI clipboard utility
    pw-volume     # for volume control w/ sway
    grim          # screenshot
    slurp         # select region on screen
    swappy        # draw on image, mostly for screenshots
    scythe        # screenshot on dmenu, grim, slurp, swappy
    swayimg       # image viewer
    qpwgraph      # gui for audio
    light         # backlight controller
    # Utils
    tree          # fs vis
    ranger        # CLI file explorer
    zathura       # pdf viewer
    jq            # CLI json explorer
    run-cwd       # script to open window from focused
    gcc           # needed for neovim
    # R
    rstudio-env
    pandoc
    texlive-env
    # Typical applications
    google-chrome
    spotify
    discord
  ];
  programs.vim = {
    enable = true;
    defaultEditor = true;
    extraConfig = ''
      set re=0
      syntax on
      filetype on
      set number
      set smartindent
      set tabstop=4
      set softtabstop=4
      set shiftwidth=4
      set expandtab
      " Highlight all search matches
      set hlsearch

      " Don't copy line numbers
      set mouse+=a

      " Open files to last position
      if has("autocmd")
          au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$")
              \| exe "normal! g`\"" | endif
      endif
    '';
  };
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
  programs.bash = {
    enable = true;
    shellAliases = {
      ranger = ". ranger";
    };
  };
  programs.firefox.enable = true;
  programs.alacritty = {
    enable = true;
  };
  programs.nheko.enable = true;





  # SSH config
  home.file.".ssh/config".text = ''
    Host csil-server
        HostName csil-cpu2.csil.sfu.ca
        User dhpham
        Port 24
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h

    Host csil-tunnel
        HostName csil-cpu3.csil.sfu.ca
        User dhpham
        Port 24
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h

    Host csil-client
        HostName csil-cpu6.csil.sfu.ca
        User dhpham
        Port 24
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h

    Host *.csil.sfu.ca
        User dhpham
        Port 24
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h
  '';
}
