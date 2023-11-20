{ config, pkgs, ... }:

{
  imports = [ ./virtualbox-iso/installer/cd-dvd/installation-cd-minimal.nix ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    vim wget git
  ];
  programs.vim.defaultEditor = true;

  documentation = {
    enable = true;
    man.enable = true;
    man.generateCaches = true;
    dev.enable = true;
    info.enable = true;
    doc.enable = true;
    nixos.enable = true;
  };

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ALL = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };
}

