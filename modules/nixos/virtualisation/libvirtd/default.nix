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
    programs.dconf.enable = true; # virt-manager requires dconf to be enabled
    programs.virt-manager.enable = true;
    virtualisation.libvirtd.enable = true;
    virtualisation.libvirtd.qemu.runAsRoot = true;
    virtualisation.libvirtd.extraConfig = mkIf (config.networking.nftables.enable) ''
      firewall_backend = "nftables"
    '';

    # disable netfilter on the virtual bridge device
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
    };

    #virtualisation.libvirtd.extraOptions = [ "--verbose" "--config" "/etc/libvirt/network.conf" ];
    #environment.etc."libvirt/network.conf".text = ''
    #  firewall_backend = "nftables"
    #'';
  };
}
