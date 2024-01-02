{ config, pkgs, ... }:

{
  imports = [ ../../programs/dwl.nix ];
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "dhpham";
  home.homeDirectory = "/home/dhpham";
  home.stateVersion = "23.05"; # Please read the comment before changing.
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

  # Graphics
  services.kanshi = {
    enable = true;
    profiles = {
      desktop = {
        outputs = [
          { 
            criteria = "Virtual-1";
            mode = "2560x1440";
          }
        ];
      };
    };
  };

  # General package stuff
  home.packages = with pkgs; [
    tree
    alacritty
    dconf       # GTK theming/settings
    # Wayland stuff
    bemenu        # launcher menu
    alacritty     # terminal emulator
    kanshi        # display settings daemon
    wdisplays     # gui for display settings
    wl-clipboard  # CLI clipboard utility
    ranger
  ];
  programs.vim = {
    enable = true;
    defaultEditor = true;
    extraConfig = ''
      set re=0
      syntax on
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
  programs.dwl = {
    enable = true;
    conf = ./dwl/dwl-config.def.h;
    cmd = {
      terminal = "${pkgs.alacritty}/bin/alacritty";
      # terminal = "alacritty";
    };
  };


  home.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS     = "1";        # To fix wlroots on VMs
    NIXOS_OZONE_WL              = "1";        # Tell electron apps to use Wayland
    # MOZ_ENABLE_WAYLAND          = "1";        # Tell Firefox to use Wayland
    BEMENU_BACKEND              = "wayland";
    GDK_BACKEND                 = "wayland";
    XDG_CURRENT_DESKTOP         = "dwl";
  };
}
