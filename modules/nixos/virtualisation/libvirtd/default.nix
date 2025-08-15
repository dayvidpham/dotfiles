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
    bridgeTrustedIface = mkOption {
      default = true;
      description = "allow traffic in-and-out of the virtual bridge iface virbr0";
      example = "true";
    };
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
    networking.firewall.checkReversePath = "loose";
    networking.firewall.trustedInterfaces = mkIf cfg.bridgeTrustedIface [ "virbr0" ];

    boot.kernel.sysctl = {
      # Enable IPv4 multicast forwarding
      "net.ipv4.conf.all.mc_forwarding" = 1;
      "net.ipv4.conf.default.mc_forwarding" = 1;

      # General forwarding (prerequisite)
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv4.conf.default.forwarding" = 1;

      # Disable strict reverse path filtering globally
      "net.ipv4.conf.all.rp_filter" = 0;
      "net.ipv4.conf.default.rp_filter" = 1; # Keep strict for new interfaces

      # IGMP settings for better multicast handling
      "net.ipv4.conf.all.force_igmp_version" = 2;
      "net.ipv4.igmp_max_memberships" = 20;

      # Increase socket buffers for multicast bursts
      "net.core.rmem_max" = 67108864;
      "net.core.netdev_max_backlog" = 2000;

      # Disable bridge netfilter processing so no mangling between VM and host iptables
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
    };

    # udev rules for automatic bridge configuration
    services.udev.extraRules = ''
      SUBSYSTEM=="net", ACTION=="add", KERNEL=="virbr*", RUN+="${pkgs.bash}/bin/bash -c 'echo 1 > /sys/class/net/%k/bridge/multicast_querier'"
      SUBSYSTEM=="net", ACTION=="add", KERNEL=="virbr*", RUN+="${pkgs.bash}/bin/bash -c 'echo 2 > /sys/class/net/%k/bridge/multicast_router'"
    '';
  };
}
