{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
let
  inherit (lib)
    mkForce
  ;
in
{
  # NOTE: Hyprland
  CUSTOM.wayland.windowManager.hyprland = {
    enable = mkForce false;
  };
  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = mkForce false;
  };
}
