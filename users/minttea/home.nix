{ config
, pkgs
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
in
rec {
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  nix.gc = {
    automatic = true;
    persistent = true;
    frequency = "4 days";
  };

  home.username = "minttea";
  home.homeDirectory = "/home/minttea";
  home.stateVersion = "23.11"; # Please read the comment before changing.

  # cursorTheme, GTK theme, ...
  CUSTOM.theme.enable = true;

  # Env vars
  home.sessionVariables = {
    XDG_CONFIG_HOME = "${config.xdg.configHome}";
    XDG_CACHE_HOME = "${config.xdg.cacheHome}";
    XDG_DATA_HOME = "${config.xdg.dataHome}";
    XDG_STATE_HOME = "${config.xdg.stateHome}";
  };

  # Virtualisation
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];
    };
  };

  #####################
  # NOTE: Desktop Environment

  # NOTE: Hyprland
  CUSTOM.wayland.windowManager.hyprland = {
    enable = true;
  };

  # NOTE: General package stuff
  home.packages = with pkgs; [
    # Wayland stuff
    bemenu # launcher menu
    wdisplays # gui for display settings
    wl-clipboard-rs # Rust CLI clipboard utility
    pw-volume # for volume control w/ sway
    grim # screenshot
    slurp # select region on screen
    swappy # draw on image, mostly for screenshots
    swayimg # image viewer
    qpwgraph # gui for audio
    light # backlight controller
    # Utils
    tree # fs vis
    ranger # CLI file explorer
    zathura # pdf viewer
    jq # CLI json explorer
    fastfetch # C implmentation of neofetch
    nvtopPackages.full # htop but for GPUs
    # R
    rstudio-env
    pandoc
    texlive-env
    # Typical user applications
    google-chrome
    spotify
    discord
    discord-screenaudio
    # Gaming
    protonup
  ];

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
    settings = {
      window.opacity = 0.8;
    };
  };
  programs.nheko.enable = true;

  programs.obs-studio.enable = true; # Grab OBS 

  ######################################
  # NOTE: Gaming
  home.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "${home.homeDirectory}/.steam/root/compatibilitytools.d";
  };


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
