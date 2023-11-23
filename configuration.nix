{ config, pkgs, ... }:

{
  imports = [ ./virtualbox-iso/installer/cd-dvd/installation-cd-minimal.nix ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    vim wget git
  ];
  programs.vim.defaultEditor = true;
  programs.git = {
    enable = true;
    config = {
      init.defaultBranch = "main";
      core.editor = "vim";
      user.email = "dayvidpham@gmail.com";
      user.name = "dayvidpham";
    };
  };

  programs.hyprland {
    enable = true;
    nvidiaPatches = true;
    xwayland.enable = true;
  };
  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1";
  };
  hardware = {
    opengl.enable = true;
    nvidia.modesetting.enable = true;
  };

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

