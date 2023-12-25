{ config, pkgs, ... }:

let
  getIconsFrom = url: hash: name:
    # could abstract out $out/share/icons in the future
    pkgs.runCommand "moveUp" {} ''
      mkdir -p $out/share/icons
      ln -s ${pkgs.fetchzip {
        url = url;
        hash = hash;
      }} $out/share/icons/${name}
    '';
  bibataCursorTheme = rec {
    name = "Bibata-Modern-Classic";
    size = 24;
    package = getIconsFrom "https://github.com/ful1e5/bibata/archive/refs/tags/v1.0.0.beta.0.tar.gz"
                           "sha256-pS0auKGpJpVFaJf1FeYi5Rcu3mH3CZZhj78LRRTjAOo="
                           name;
  };
in {
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "dhpham";
  home.homeDirectory = "/home/dhpham";
  home.stateVersion = "23.05"; # Please read the comment before changing.
  home.pointerCursor = {
      gtk.enable = true;
      inherit (bibataCursorTheme) name size package;
  };
  gtk = {
    enable = true;
    cursorTheme = {
      inherit (bibataCursorTheme) name size package;
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
    firefox
    tree
    alacritty
    dconf
  ];
  programs.vim = {
    enable = true;
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

  # Enable nix-direnv for convenience
  programs = {
    direnv = {
      enable = true;
      enableBashIntegration = true;
      nix-direnv.enable = true;
    };

    bash.enable = true;
  };

  # Env variables
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };
}
