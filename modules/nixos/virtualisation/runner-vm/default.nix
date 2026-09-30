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
        default = 4096;
        description = "Memory in MiB per runner VM.";
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
              inherit (cfg.vm) vcpu mem;
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
      systemd.services = lib.listToAttrs (map (i: {
        name = "microvm@runner-vm-${toString i}";
        value = {
          serviceConfig.Restart = lib.mkForce "no";
          # The slot's virtiofsd children exit 0 when the VM stops and their
          # supervisor never respawns them (an expected exit needs no
          # restart), so the unit stays green while serving stale sockets and
          # the next boot dies connecting to them. Restart the daemons on
          # every boot; the `+` runs this as root because the VM unit itself
          # runs as the microvm user.
          serviceConfig.ExecStartPre = lib.mkBefore [
            "+${pkgs.systemd}/bin/systemctl try-restart microvm-virtiofsd@runner-vm-${toString i}.service"
          ];
        };
      }) slots);

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
