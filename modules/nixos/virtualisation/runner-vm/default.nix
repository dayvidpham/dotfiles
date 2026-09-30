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
, infra ? null
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

    dispatcher = {
      enable = lib.mkEnableOption "the scale-set dispatcher driving the VM slots";

      scaleSetName = lib.mkOption {
        type = lib.types.str;
        default = "desktop-microvm";
        description = "Runner scale set name; also the workflow label.";
      };
      runnerGroup = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Runner group the scale set registers in.";
      };
      labels = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "self-hosted" "container" ];
        description = "Extra labels carried by the scale set.";
      };
      heartbeatRepo = lib.mkOption {
        type = lib.types.str;
        default = "peasant-labs/infra";
        description = "Repository holding the pool-health variable the router reads.";
      };
      heartbeatVariable = lib.mkOption {
        type = lib.types.str;
        default = "RUNNER_POOL_HEALTH";
        description = "Repository variable for the pool-health record.";
      };
      app = {
        clientId = lib.mkOption {
          type = lib.types.str;
          description = "GitHub App client id used for scale sets, JIT and the heartbeat.";
        };
        installationId = lib.mkOption {
          type = lib.types.int;
          description = "GitHub App installation id on the organization.";
        };
        privateKeyFile = lib.mkOption {
          type = lib.types.path;
          description = "PEM private key (root-readable, e.g. a sops secret path).";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.cacheHostPath} 0755 root root -"
        "d ${cfg.jitHostPath} 0700 root root -"
      ] ++ map (i: "d ${cfg.jitHostPath}/runner-vm-${toString i} 0700 root root -") slots;
    }

    (lib.mkIf hasMicrovm {
      microvm.host.enable = true;

      microvm.vms = lib.listToAttrs (map (i: {
        name = "runner-vm-${toString i}";
        value = {
          inherit pkgs;
          config = { ... }: {
            imports = [ ./guest.nix ];
            CUSTOM.virtualisation.runner-vm.guest = {
              slot = i;
              inherit (cfg.vm) vcpu mem;
              cacheHostPath = cfg.cacheHostPath;
              jitHostPath = "${cfg.jitHostPath}/runner-vm-${toString i}";
              mac = macFor i;
              inherit (cfg) runnerImage runnerImageName;
            };
          };
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

    (lib.mkIf cfg.dispatcher.enable {
      assertions = [
        {
          assertion = infra != null;
          message = "CUSTOM.virtualisation.runner-vm.dispatcher requires the infra flake input";
        }
      ];

      systemd.services.runner-dispatcher = {
        description = "GitHub runner pool dispatcher (scale set to per-job VMs)";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs (
            [ "${infra.packages.${pkgs.stdenv.hostPlatform.system}.runner-dispatcher}/bin/runner-dispatcher" ]
            ++ [
              "-scale-set-name" cfg.dispatcher.scaleSetName
              "-runner-group" cfg.dispatcher.runnerGroup
              "-labels" (lib.concatStringsSep "," cfg.dispatcher.labels)
              "-max-capacity" (toString cfg.count)
              "-vm-driver" "systemd"
              "-vm-jit-dir" cfg.jitHostPath
              "-heartbeat-repo" cfg.dispatcher.heartbeatRepo
              "-heartbeat-variable" cfg.dispatcher.heartbeatVariable
              "-app-client-id" cfg.dispatcher.app.clientId
              "-app-installation-id" (toString cfg.dispatcher.app.installationId)
              "-app-private-key-file" (toString cfg.dispatcher.app.privateKeyFile)
            ]
          );
          Restart = "always";
          RestartSec = "5s";
        };
      };
    })
  ]);
}
