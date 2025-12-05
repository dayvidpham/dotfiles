{ config
, pkgs
, pkgs-stable
, pkgs-unstable
, lib
, osConfig
, ...
}:
let
  inherit (lib)
    mkDefault
    ;
in
rec {
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  nix.gc = {
    automatic = true;
    dates = [ "weekly" ];
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

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/mailto" = "firefox.desktop";
      "x-scheme-handler/http" = "firefox.desktop";
      "x-scheme-handler/https" = "firefox.desktop";
      "x-scheme-handler/webcal" = "firefox.desktop";
      "x-scheme-handler/about" = "firefox.desktop";
      "x-scheme-handler/unknown" = "firefox.desktop";
      "x-scheme-handler/chrome" = "firefox.desktop";
      "text/html" = "firefox.desktop";
      "application/x-extension-htm" = "firefox.desktop";
      "application/x-extension-html" = "firefox.desktop";
      "application/x-extension-shtml" = "firefox.desktop";
      "application/xhtml+xml" = "firefox.desktop";
      "application/x-extension-xhtml" = "firefox.desktop";
      "application/x-extension-xht" = "firefox.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" = "firefox.desktop";

      "inode/directory" = "dolphin.desktop";
      "image/*" = "imv.desktop";
      "image/png" = "imv.desktop";
    };
  };

  # Virtualisation
  CUSTOM.services.podman.enable = true;
  CUSTOM.programs.distrobox.enable = true;

  #####################
  # NOTE: Desktop Environment
  CUSTOM.services.kanshi.enable = true;

  # NOTE: Hyprland
  CUSTOM.wayland.windowManager.hyprland = {
    enable = mkDefault true;
  };
  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = mkDefault true;
  };

  # NOTE: niri, experimental
  CUSTOM.wayland.windowManager.niri.enable = true;


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
    imv # image viewer
    qpwgraph # gui for audio
    brightnessctl # device light controller

    # Desktop
    kdePackages.dolphin
    kdePackages.qtsvg

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
    dragon-drop # X/Wayland drag and drop
    steam-run-free # run things in steam's FHS env
    gimp # photo editing/markup
    kdePackages.dolphin # file explorer
    scythe # self-rolled screenshotter

    # For SFU
    openfortivpn
    openfortivpn-webview-qt

    # Typical user applications
    google-chrome
    spotify
    discord

    # Cloud
    oci-cli
    openssl
  ])
  ++ (with pkgs-unstable; [
    # Utils
    neovide # Rust-based native nvim text editor
    nix-search # Fast, indexed replacement for awful builtin `nix search`

    # Notes
    #anytype # proj management/knowledge base
    zotero # ref/citation/bib manager
    #lorien # infinite canvas notes
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

  CUSTOM.programs.vscode.enable = true;
  CUSTOM.programs.opencode.enable = true;

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
      "--height '40%'"
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

  ##############################
  # General applications
  programs.imv.enable = true;
  programs.imv.package = pkgs.imv;
  xdg.desktopEntries.imv = {
    name = "imv";
    genericName = "Image Viewer";
    exec = "${programs.imv.package}/bin/imv";
    terminal = false;
    categories = [ "Graphics" "Viewer" ];
    mimeType = [ "image/*" ];
  };

  programs.firefox.enable = true;
  programs.firefox.package = pkgs-stable.firefox-bin;

  programs.obs-studio.enable = true;
  programs.lazygit.enable = true;

  # SSH config

  home.file.".ssh/config".source = config.lib.file.mkOutOfStoreSymlink /home/minttea/dotfiles/users/minttea/ssh/config;
}
