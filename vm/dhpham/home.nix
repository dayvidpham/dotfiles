{ config, pkgs, ... }:

{
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "dhpham";
  home.homeDirectory = "/home/dhpham";
  home.stateVersion = "23.05"; # Please read the comment before changing.

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
