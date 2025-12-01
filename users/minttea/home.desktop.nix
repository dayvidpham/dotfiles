{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
{
  home.packages = (with pkgs; [
    # Gaming
    protonup-ng
    #godot
    unityhub

  ])
  ++ (with pkgs-unstable; [
    # CAD viewer
    #blender
  ])
  ;

  CUSTOM.games.minecraft.enable = false;
  programs.lutris.enable = true;

  CUSTOM.services.syncthing.enable = true;
}
