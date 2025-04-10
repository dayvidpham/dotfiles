{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:

rec {
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  nix.gc = {
    automatic = true;
    frequency = "weekly";
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
  CUSTOM.podman.enable = true;

  dconf.enable = true;
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
  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = true;
  };
  CUSTOM.services.kanshi.enable = true;

  #####################
  # NOTE: General programs and packages
  home.packages = (with pkgs; [

    # Wayland stuff
    wdisplays # gui for display settings
    wl-clipboard-rs # Rust CLI clipboard utility
    clipse # CLI clipboard manager
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
    kdePackages.okular # fully-featured pdf viewer
    jq # CLI json explorer
    fastfetch # C implmentation of neofetch
    nvtopPackages.full # htop but for GPUs
    mpv # CLI media player
    haruna # mpv Qt/QML frontend for mpv
    vimiv-qt # image viewer with vim bindings
    xdragon # X/Wayland drag and drop
    steam-run-free # run things in steam's FHS env

    # For SFU
    openfortivpn
    openfortivpn-webview-qt

    # Typical user applications
    google-chrome
    spotify
    discord
    discord-screenaudio
    zotero # ref/citation/bib manager
    vivaldi # alternative Chromium browser
    anytype # proj management/knowledge base

    # Gaming
    protonup
  ])
  ++ (with pkgs-unstable; [
    # Utils
    neovide # Rust-based native nvim text editor
    nix-search # Fast, indexed replacement for awful builtin `nix search`
  ]);


  #########################
  # Programming Envs

  CUSTOM.programs.nodejs.enable = true;
  CUSTOM.programs.rEnv.enable = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config = {
      global = {
        hide_env_diff = true;
      };
    };
  };


  #########################
  # General CLI tools

  # NOTE: Zsh setup
  # Manual setup: don't like how home-manager currently sets up zsh
  CUSTOM.programs.zsh.enable = true;
  programs.atuin = {
    enable = false;
    enableZshIntegration = false;
    settings = {
      style = "compact";
      inline_height = 30;
      enter_accept = false;
    };
  };
  programs.zoxide = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
  };
  programs.bat = {
    enable = true;
    extraPackages =
      let
        batPkgAttrs = lib.filterAttrs (key: val: lib.isType "package" val) pkgs.bat-extras;
        batPkgs = lib.mapAttrsToList (key: val: val) batPkgAttrs;
      in
      batPkgs;
  };
  programs.fzf = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
    colors = {
      "fg" = "#d0d0d0";
      "fg+" = "#d0d0d0";
      "bg" = "-1";
      "bg+" = "#262626";

      "hl" = "#5f87af";
      "hl+" = "#5fd7ff";
      "info" = "#afaf87";
      "marker" = "#80c9b8";

      "prompt" = "#80c9b8";
      "spinner" = "#9fffd9";
      "pointer" = "#e27739";
      "header" = "#87afaf";

      "border" = "#374142";
      "preview-scrollbar" = "#000000";
      "label" = "#aeaeae";
      "query" = "#d9d9d9";
    };
    defaultOptions = [
      "--border='rounded'"
      "--border-label='~ (fuzzy)'"
      "--border-label-pos='1'"
      "--preview-window='border-rounded'"
      "--prompt='> '"
      "--marker='>'"
      "--pointer='◆'"
      "--separator='─'"
      "--scrollbar='│'"
      "--info='right'"
      "--height 40%"
    ];
  };
  programs.eza = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
    icons = "auto";
    colors = "always";
    extraOptions =
      [
        "--group-directories-first"
        "--header"
      ];
  };

  programs.firefox.enable = true;

  CUSTOM.programs.ghostty.enable = true;

  programs.obs-studio.enable = true;
  programs.lazygit.enable = true;

  # SSH config

  home.file.".ssh/config".source = config.lib.file.mkOutOfStoreSymlink ./ssh/config;
}
