{ config
, pkgs
, ...
}:

rec {
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  nix.gc = {
    automatic = true;
    frequency = "7 days";
  };

  home.username = "minttea";
  home.homeDirectory = "/home/minttea";
  home.stateVersion = "24.05"; # Please read the comment before changing.

  # cursorTheme, GTK theme, ...
  CUSTOM.theme.enable = true;

  # Env vars
  home.sessionVariables = {
    XDG_CONFIG_HOME = "${config.xdg.configHome}";
    XDG_CACHE_HOME = "${config.xdg.cacheHome}";
    XDG_DATA_HOME = "${config.xdg.dataHome}";
    XDG_STATE_HOME = "${config.xdg.stateHome}";
  };

  #####################
  # NOTE: Desktop Environment

  # NOTE: Hyprland
  CUSTOM.wayland.windowManager.hyprland = {
    enable = true;
  };

  #####################
  # NOTE: General programs and packages
  home.packages = with pkgs; [
    # Wayland stuff
    wdisplays # gui for display settings
    wl-clipboard # CLI clipboard utility
    pw-volume # for volume control w/ sway
    grim # screenshot
    slurp # select region on screen
    swappy # draw on image, mostly for screenshots
    swayimg # image viewer
    qpwgraph # gui for audio
    brightnessctl # device light controller
    # Utils
    tree # fs vis
    ranger # CLI file explorer
    zathura # pdf viewer
    jq # CLI json explorer
    fastfetch # C implmentation of neofetch
    nvtopPackages.full # htop but for GPUs
    mpv # media player
    vimiv-qt # image viewer with vim bindings
    # Typical user applications
    google-chrome
    spotify
    discord
    discord-screenaudio
    # Gaming
    protonup
    steam-run
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  # NOTE: Zsh setup
  # Manual setup: don't like how home-manager currently sets up zsh
  CUSTOM.programs.zsh.enable = true;

  programs.firefox.enable = true;

  programs.alacritty = {
    enable = true;
    settings = {
      window.opacity = 0.8;
    };
  };

  programs.nheko.enable = true;

  CUSTOM.programs.rEnv.enable = true;

  programs.lazygit.enable = true;

  # SSH config
  home.file.".ssh/config".text = ''
    Host csil
        HostName csil-cpu2.csil.sfu.ca
        User dhpham
        Port 24
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h

    Host github.com
        User dayvidpham
        Port 22
        ControlPath ${home.homeDirectory}/.ssh/socket.%r@%h:%p
        ControlMaster auto
        ControlPersist 2h
  '';
}
