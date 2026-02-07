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
    enable = false;
  };
  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = false;
  };

  programs.opencode.enable = true;
  CUSTOM.services.syncthing.enable = true;
  CUSTOM.services.syncthing.secrets = {
    enable = true;
    apiKeyFile = "/run/secrets/syncthing/apikey";
  };
}
