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

    # CAD viewer
    f3d
    #paraview
  ];

  CUSTOM.games.minecraft.enable = false;
  programs.lutris.enable = true;
}
