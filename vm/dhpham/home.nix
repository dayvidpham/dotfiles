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
  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    firefox
    tree
    alacritty
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".vimrc".text = ''
      set re=0
      syntax on
      set number
      set smartindent
      set tabstop=4
      set softtabstop=4
      set shiftwidth=4
      set expandtab
    '';
  };

  # Env variables
  home.sessionVariables = {
    EDITOR = "vim";
    VISUAL = "vim";
  };
}
