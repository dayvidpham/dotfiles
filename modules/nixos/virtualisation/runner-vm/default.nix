# GitHub runner per-job microVMs (host side).
#
# Declares a fixed number of Cloud Hypervisor VM slots. The dispatcher writes a
# one-shot JIT config into a slot's directory and boots that slot; the guest
# runs exactly one job and powers off. Slots are recycled, so the guest is
# always fresh state while the shared cache directory survives.
{ config
, options
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.runner-vm;
  hasMicrovm = options ? microvm;
  slots = lib.range 1 cfg.count;

  # Locally administered MACs, one per slot.
  macFor = i: "02:00:00:00:01:${lib.fixedWidthString 2 "0" (lib.toLower (lib.toHexString i))}";
in
{
  options.CUSTOM.virtualisation.runner-vm = {
    enable = lib.mkEnableOption "GitHub runner per-job Cloud Hypervisor VMs";

    count = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "Number of runner VM slots; bounds concurrent jobs.";
    };

    vm = {
      vcpu = lib.mkOption {
        type = lib.types.int;
        default = 6;
        description = "Virtual CPUs per runner VM.";
      };
      mem = lib.mkOption {
        type = lib.types.int;
        default = 8192;
        description = "Memory in MiB per runner VM.";
      };
      diskSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 16384;
        description = ''
          Minimum size in MiB of each slot's sparse scratch disk. Existing
          images grow on the next VM start and are never shrunk automatically.
        '';
      };
      idleTimeoutSec = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = "Seconds a runner VM waits for its first job before powering off.";
      };
    };

    limits = {
      cpuQuota = lib.mkOption {
        type = lib.types.str;
        default = "${toString (cfg.count * cfg.vm.vcpu * 100)}%";
        defaultText = lib.literalExpression ''"''${toString (count * vm.vcpu * 100)}%"'';
        description = "CPUQuota for the slice holding every runner VM and its virtiofsd daemons.";
      };
      memoryMax = lib.mkOption {
        type = lib.types.str;
        default = "${toString (cfg.count * (cfg.vm.mem + 512))}M";
        defaultText = lib.literalExpression ''"''${toString (count * (vm.mem + 512))}M"'';
        description = ''
          MemoryMax for the runner VM slice: every slot's guest memory plus
          hypervisor and virtiofsd overhead. Below that, the kernel OOM-kills a
          running VM.
        '';
      };
    };

    cacheHostPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/runner-vm/cache";
      description = "Shared host directory mounted read-write in every runner VM.";
    };

    jitHostPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/runner-vm/jit";
      description = "Parent directory holding one JIT directory per slot.";
    };

    disksHostPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/runner-vm/disks";
      description = "Host directory holding one container-store disk image per slot.";
    };

    runnerImageName = lib.mkOption {
      type = lib.types.str;
      default = "quay.io/peasant-labs/github-runner:pinned";
      description = "Repository:tag the baked image is loaded as inside the guest.";
    };

    runnerImage = lib.mkOption {
      type = lib.types.package;
      description = ''
        Docker-archive tarball of the signed runner image, loaded into the
        guest's podman before the job starts. Pin the digest and fill the
        output hash from the first build (see pkgs.dockerTools.pullImage).
      '';
      default = pkgs.dockerTools.pullImage {
        imageName = "quay.io/peasant-labs/github-runner";
        imageDigest = "sha256:078b20f289f2852c45a92b862894536624b90e759ce9ff2e405b12db9ca565ae";
        finalImageTag = "pinned";
        os = "linux";
        arch = "amd64";
        # Output hash of the fetched image tarball; re-fetched and re-hashed
        # whenever the digest or the dockerTools implementation changes.
        sha256 = "sha256-Xa6JMWt7SQmmyb58IsoqT2DsuGxm5ozWrD41kwaQ2aE=";
      };
    };

    network = {
      bridge = lib.mkOption {
        type = lib.types.str;
        default = "runner-br";
        description = "Host bridge carrying the runner tap interfaces.";
      };
      subnet = lib.mkOption {
        type = lib.types.str;
        default = "10.77.0";
        description = "Private /24 for the runner bridge; guests get DHCP from the host.";
      };
      externalInterface = lib.mkOption {
        type = lib.types.str;
        default = "enp8s0";
        description = "Upstream interface used for NAT.";
      };
    };

    bypassExitNode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep runner guest traffic on the physical uplink when a Tailscale exit
        node is active. An exit node changes the host's default route and can
        route the bridge subnet into the tunnel; Tailscale forwards the host's
        own traffic but does not NAT packets arriving from the guest bridge, so
        those packets are dropped and the runner never reaches GitHub. The
        policy rules added here match the bridge before the exit node's
        catch-all rule, so the host keeps using the exit node while the guests
        use the normal uplink.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.cacheHostPath} 0755 root root -"
        "d ${cfg.jitHostPath} 0700 root root -"
        # The VM service runs as microvm:kvm (constants in microvm.nix) and
        # creates and opens its own volume image, so this directory must be
        # writable by that user. microvm.nix adjusts share sources itself;
        # volumes are outside that mechanism.
        "d ${cfg.disksHostPath} 0700 microvm kvm -"
      ] ++ map (i: "d ${cfg.jitHostPath}/runner-vm-${toString i} 0700 root root -") slots;
    }

    (lib.mkIf hasMicrovm {
      microvm.host.enable = true;

      microvm.vms = lib.listToAttrs (map (i: {
        name = "runner-vm-${toString i}";
        value = {
          inherit pkgs;
          # Slots are demand-started by the dispatcher; without this, systemd
          # boots all of them at boot and the pool holds four idle VMs (and
          # their memory) until the first job.
          autostart = false;
          config = { ... }: {
            imports = [ ./guest.nix ];
            CUSTOM.virtualisation.runner-vm.guest = {
              slot = i;
              inherit (cfg.vm) vcpu mem diskSize idleTimeoutSec;
              cacheHostPath = cfg.cacheHostPath;
              jitHostPath = "${cfg.jitHostPath}/runner-vm-${toString i}";
              disksHostPath = cfg.disksHostPath;
              mac = macFor i;
              inherit (cfg) runnerImage runnerImageName;
            };
          };
        };
      }) slots);

      # Slots are per-job: when the guest powers off, the unit must stay
      # inactive so the dispatcher can reclaim it. The microvm.nix template
      # restarts always — right for long-lived VMs, a boot loop for one-shot
      # slots.
      #
      # Every VM and its virtiofsd daemons share one slice, the host-protection
      # ceiling for the pool (the container pool has the same kind of parent).
      systemd.services = lib.listToAttrs (lib.concatMap (i: [
        {
          name = "microvm@runner-vm-${toString i}";
          value.serviceConfig = {
            Restart = lib.mkForce "no";
            Slice = "runner-vm.slice";
          };
        }
        {
          name = "microvm-virtiofsd@runner-vm-${toString i}";
          value.serviceConfig.Slice = "runner-vm.slice";
        }
      ]) slots) // {
        # Keep runner traffic on the physical uplink even while a Tailscale exit
        # node is active. An exit node installs a catch-all policy rule
        # (`from all lookup 52` -> `default via tailscale0`) and can learn the
        # bridge subnet into that table, so guest packets would otherwise enter
        # the tunnel with a private source address. Tailscale forwards the
        # host's own traffic; it does not NAT traffic arriving from another
        # interface, so those packets are dropped and the runner never
        # registers.
        #
        # A lower priority number wins. These rules match the bridge before the
        # catch-all rule, so guest egress and host-to-guest traffic use `main`
        # (the physical default) while the host itself keeps using the exit
        # node.
        runner-vm-policy-routes = lib.mkIf cfg.bypassExitNode {
          description = "Keep GitHub runner VM traffic on the physical uplink";
          wantedBy = [ "multi-user.target" ];
          wants = [ "network-online.target" ];
          after = [ "network-online.target" "systemd-networkd.service" ]
            ++ lib.optional config.services.tailscale.enable "tailscaled.service";
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "runner-vm-policy-routes" ''
              set -eu
              add_rule() {
                priority="$1"
                shift
                if ! ${pkgs.iproute2}/bin/ip rule show | grep -q "^''${priority}:"; then
                  ${pkgs.iproute2}/bin/ip rule add "$@" priority "$priority"
                fi
              }
              add_rule 5200 from ${cfg.network.subnet}.0/24 lookup main
              add_rule 5201 to ${cfg.network.subnet}.0/24 lookup main
              add_rule 5202 iif ${cfg.network.bridge} lookup main
            '';
          };
        };
      };

      systemd.slices.runner-vm = {
        description = "Per-job GitHub runner VMs";
        sliceConfig = {
          CPUQuota = cfg.limits.cpuQuota;
          MemoryMax = cfg.limits.memoryMax;
        };
      };

      # Outbound-only networking: one bridge, a DHCP server for guests, and
      # NAT for everything behind it.
      systemd.network.netdevs."10-runner-vm-bridge".netdevConfig = {
        Kind = "bridge";
        Name = cfg.network.bridge;
      };
      systemd.network.networks."10-runner-vm-bridge" = {
        matchConfig.Name = cfg.network.bridge;
        networkConfig.DHCPServer = true;
        addresses = [ { addressConfig.Address = "${cfg.network.subnet}.1/24"; } ];
      };
      systemd.network.networks."11-runner-vm-taps" = {
        matchConfig.Name = "runner-vm-*";
        networkConfig.Bridge = cfg.network.bridge;
      };
      networking.firewall.allowedUDPPorts = [ 67 ];
      networking.nat = {
        enable = true;
        internalInterfaces = [ cfg.network.bridge ];
        externalInterface = cfg.network.externalInterface;
      };
    })
  ]);
}
