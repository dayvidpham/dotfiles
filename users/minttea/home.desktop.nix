{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
{
  home.packages = with pkgs; [
    # Gaming
    protonup-ng
    godot
    unityhub
  ];

  CUSTOM.games.minecraft.enable = false;
  programs.lutris.enable = true;
}
