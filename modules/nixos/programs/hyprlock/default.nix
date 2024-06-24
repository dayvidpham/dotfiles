{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let

  cfg = config.CUSTOM.programs.hyprlock;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.programs.hyprlock = {
    enable = mkEnableOption ''
      Program to lock the screen, integrated with Hyprland.
      Creates the required attribute on `security.pam.services` to enable authentication from lock screen.
    '';
  };

  config = mkIf cfg.enable {
    security.pam.services.hyprlock = { };
  };
}
