{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.libvirtd;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.virtualisation.libvirtd = {
    enable = mkEnableOption "common shared libvirtd settings";
  };

  config = mkIf cfg.enable {
    # Virtualisation
    dconf.enable = true; # virt-manager requires dconf to be enabled
    dconf.settings = {
      "org/virt-manager/virt-manager/connections" = {
        autoconnect = [ "qemu:///system" ];
        uris = [ "qemu:///system" ];
      };
    };
  };
}
