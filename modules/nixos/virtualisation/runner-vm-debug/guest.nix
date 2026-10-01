# Debug runner VM (standalone, user-runnable).
#
# A NixOS guest that mirrors the parts of the production runner VM that matter
# for debugging (systemd-networkd policy, podman, netfilter modules, ip
# forwarding), but is started by a normal user with cloud-hypervisor and a
# passt vhost-user NIC: no tap, no host module, no root.
#
# Run it with scripts/runner-vm-debug (build/run/ssh/stop). ssh is forwarded
# to a local port, root login by key only.
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.CUSTOM.virtualisation.runner-vm-debug.guest;
in
{
  options.CUSTOM.virtualisation.runner-vm-debug.guest = {
    vcpu = mkOption {
      type = types.int;
      default = 6;
      description = "Virtual CPUs.";
    };
    mem = mkOption {
      type = types.int;
      default = 4096;
      description = "Memory in MiB.";
    };
    mac = mkOption {
      type = types.str;
      default = "02:00:00:00:01:db";
      description = "MAC of the virtio NIC; must match the passt backend.";
    };
    passtSocket = mkOption {
      type = types.str;
      default = "/run/user/1000/runner-vm-debug/passt.sock";
      description = "Host unix socket passt listens on for the vhost-user NIC.";
    };
    apiSocket = mkOption {
      type = types.str;
      default = "/run/user/1000/runner-vm-debug/vm.sock";
      description = "Cloud Hypervisor API socket (enables microvm-shutdown).";
    };
    diskImage = mkOption {
      type = types.str;
      default = "/home/minttea/.local/share/runner-vm-debug/disk.img";
      description = ''
        Scratch disk for container storage. Created and formatted by the
        runner on first start, as the user that starts the VM.
      '';
    };
    diskSize = mkOption {
      type = types.ints.positive;
      default = 24576;
      description = "Maximum size in MiB of the scratch disk.";
    };
    shareHostPath = mkOption {
      type = types.str;
      default = "/home/minttea/.local/share/runner-vm-debug/share";
      description = "Host directory shared read-write into the debug VM.";
    };
    virtiofsdSocket = mkOption {
      type = types.str;
      default = "/run/user/1000/runner-vm-debug/virtiofsd.sock";
      description = ''
        Socket the user-run virtiofsd listens on. The share also makes Cloud
        Hypervisor use shared memory, which its vhost-user net device requires.
      '';
    };
    sshKeys = mkOption {
      type = types.listOf types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbEq1/i8sCEuKZV5xFr+S5T12u54kEyqYHqD2/Xu2kX minttea@desktop"
      ];
      description = "Authorized keys for root ssh.";
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "runner-vm-debug";

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = cfg.vcpu;
      mem = cfg.mem;
      socket = cfg.apiSocket;
      # The NIC comes from a passt backend over vhost-user, so the runner
      # never needs a tap (which would need root) or /dev/vhost-net.
      cloud-hypervisor.extraArgs = [
        "--net"
        "vhost_user=true,socket=${cfg.passtSocket},mac=${cfg.mac}"
      ];
      volumes = [
        {
          image = cfg.diskImage;
          mountPoint = "/var/lib/containers";
          size = cfg.diskSize;
        }
      ];
      shares = [
        {
          tag = "share";
          source = cfg.shareHostPath;
          mountPoint = "/mnt/share";
          proto = "virtiofs";
          socket = cfg.virtiofsdSocket;
        }
      ];
      graphics.enable = false;
    };

    # Mirrors the production guest: physical links only, DHCP from the uplink
    # (passt here). A container veth carries a link kind ("veth") and must
    # stay under podman/netavark's control: networkd detaches a link it
    # manages from a master its .network file does not name
    # (link_request_to_set_master() in networkd), which silently unplugs a
    # container veth from its podman bridge.
    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.network.networks."10-ether" = {
      matchConfig = {
        Type = "ether";
        Kind = "!*";
      };
      networkConfig.DHCP = "yes";
      linkConfig.RequiredForOnline = "routable";
    };

    services.openssh = {
      enable = true;
      settings.PermitRootLogin = "prohibit-password";
    };
    users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;
    networking.firewall.allowedTCPPorts = [ 22 ];

    # Same container stack as production: the netfilter modules are loadable
    # in the guest kernel and nothing loads them unless asked, and the bridge
    # network needs forwarding.
    boot.kernelModules = [
      "nf_tables"
      "nf_nat"
      "nft_nat"
      "nft_masq"
      "nft_chain_nat"
      "nft_compat"
    ];
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.forwarding" = 1;
    };
    virtualisation.podman.enable = true;
    virtualisation.containers.enable = true;
    systemd.sockets.podman.wantedBy = [ "sockets.target" ];

    # Debugging tools. The store is read-only in the guest, so anything we
    # want inside has to be in this list.
    environment.systemPackages = with pkgs; [
      iproute2
      nftables
      strace
      tcpdump
      socat
      jq
      curl
      bind
      podman
    ];

    # The host captures this VM's serial console in the terminal that runs it.
    services.journald.extraConfig = "ForwardToConsole=yes";
    documentation.enable = false;
  };
}
