{ 
  config
  , pkgs
  , nixvim
  , ... 
}:
let
  rstudio-env = pkgs.rstudioWrapper.override { 
    packages = with pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
    ];
  };
  texlive-env = (pkgs.texlive.combine {
    inherit (pkgs.texlive) scheme-full float;
  });
in rec {
  imports = [ 
    nixvim.homeManagerModules.nixvim
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

  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };

  # Graphics
  services.kanshi = {
    enable = true;
    profiles = {
      desktop = {
        outputs = [
          { 
            criteria = "eDP-1";
            mode = "1920x1200@119.90Hz";
          }
        ];
      };
    };
  };

  # Sway config
  programs.waybar = {
    enable = true;
    settings = [{
      height = 30;
      layer = "top";
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
        format = "{icon}";
        return-type = "json";
        signal = 8;
        interval = "once";
        format-icons = {
          mute = "";
          default = [ "" "" "" "" ];
        };
        exec = "pw-volume status";
        #format = "{volume}% {icon} {format_source}";
        #format-bluetooth = "{volume}% {icon} {format_source}";
        #format-bluetooth-muted = " {icon} {format_source}";
        #format-icons = {
        #  car = "";
        #  default = [ "" "" "" ];
        #  handsfree = "";
        #  headphones = "";
        #  headset = "";
        #  phone = "";
        #  portable = "";
        #};
        #format-muted = " {format_source}";
        #format-source = "{volume}% ";
        #format-source-muted = "";
        #on-click = "pavucontrol";
      };
      "sway/mode" = { format = ''<span style="italic">{}</span>''; };
      temperature = {
        critical-threshold = 80;
        format = "{temperatureC}°C {icon}";
        format-icons = [ "" "" "" ];
      };
    }];
  };
  wayland.windowManager.sway = {
    enable = true;
    config = {
      terminal = "${pkgs.alacritty}/bin/alacritty";
      output = {
        "eDP-1" = {
          mode = "1920x1200@119.90Hz";
          scale = "1.15";
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
    };
    extraConfig = ''
        bindsym XF86AudioRaiseVolume exec "pw-volume change +2.5%; pkill -RTMIN+8 waybar"
        bindsym XF86AudioLowerVolume exec "pw-volume change -2.5%; pkill -RTMIN+8 waybar"
        bindsym XF86AudioMute exec "pw-volume mute toggle; pkill -RTMIN+8 waybar" 
    '';
  };

  # General package stuff
  home.packages = with pkgs; [
    tree
    # Wayland stuff
    bemenu        # launcher menu
    kanshi        # display settings daemon
    wdisplays     # gui for display settings
    wl-clipboard  # CLI clipboard utility
    pw-volume     # for volume control w/ sway
    grim          # screenshot
    slurp         # region screenshot
    swayimg       # image viewer
    # Utils
    ranger        # CLI file explorer
    zathura       # pdf viewer
    # R
    rstudio-env
    pandoc
    texlive-env
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
  programs.nixvim = {
    enable = true;
  };
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

  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS     = "1";        # To fix wlroots on VMs
    NIXOS_OZONE_WL              = "1";        # Tell electron apps to use Wayland
    MOZ_ENABLE_WAYLAND          = "1";        # Run Firefox on Wayland
    BEMENU_BACKEND              = "wayland";
    GDK_BACKEND                 = "wayland";
    XDG_CURRENT_DESKTOP         = "sway";
  };
}
