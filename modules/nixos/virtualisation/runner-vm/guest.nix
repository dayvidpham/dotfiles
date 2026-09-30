# GitHub runner per-job microVM (guest side).
#
# Boots with the runner image already loaded, registers with a one-shot JIT
# config injected through a read-only virtiofs mount, runs exactly one job, and
# powers off. The shared cache directory is the only state that outlives the
# VM.
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.CUSTOM.virtualisation.runner-vm.guest;
in
{
  options.CUSTOM.virtualisation.runner-vm.guest = {
    slot = mkOption {
      type = types.ints.positive;
      description = "Slot number this guest belongs to.";
    };
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
      description = "Locally administered MAC for the tap interface.";
    };
    cacheHostPath = mkOption {
      type = types.str;
      description = "Host cache directory shared read-write into the guest.";
    };
    jitHostPath = mkOption {
      type = types.str;
      description = "Host directory holding this slot's JIT config.";
    };
    runnerImage = mkOption {
      type = types.package;
      description = "Docker-archive tarball loaded into podman at boot.";
    };
    runnerImageName = mkOption {
      type = types.str;
      description = "Repository:tag the image is loaded as.";
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "runner-vm-${toString cfg.slot}";

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = cfg.vcpu;
      mem = cfg.mem;
      interfaces = [
        {
          type = "tap";
          id = "runner-vm-${toString cfg.slot}";
          inherit (cfg) mac;
        }
      ];
      shares = [
        {
          tag = "cache";
          source = cfg.cacheHostPath;
          mountPoint = "/var/cache/runner";
          proto = "virtiofs";
        }
        {
          tag = "jit";
          source = cfg.jitHostPath;
          mountPoint = "/run/jit";
          proto = "virtiofs";
          # Read-only at the server: even guest root cannot write back into the
          # host directory through a remount.
          readOnly = true;
        }
      ];
      # Boot as fast as possible; no console, no graphics.
      graphics.enable = false;
    };

    fileSystems."/var/cache/runner" = {
      device = "cache";
      fsType = "virtiofs";
      options = [ "nofail" "x-systemd.mount-timeout=10" ];
    };
    fileSystems."/run/jit" = {
      device = "jit";
      fsType = "virtiofs";
      options = [ "ro" "nofail" "x-systemd.mount-timeout=10" ];
    };

    networking.useNetworkd = true;
    systemd.network.enable = true;
    systemd.network.networks."10-ether" = {
      matchConfig.Type = "ether";
      networkConfig = {
        DHCP = "yes";
        DNS = [ "1.1.1.1" "9.9.9.9" ];
      };
      linkConfig.RequiredForOnline = "routable";
    };

    virtualisation.podman.enable = true;
    virtualisation.containers.enable = true;

    # The runner image ships in the read-only Nix store; loading it costs a few
    # seconds per boot and removes every per-job registry pull.
    systemd.services.runner-image-load = {
      description = "Load the baked runner image into podman";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        ${pkgs.podman}/bin/podman load -i ${cfg.runnerImage}
      '';
    };

    # One job per VM: register with the injected JIT config, run, power off.
    systemd.services.runner-job = {
      description = "Run one GitHub Actions job and shut the VM down";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      requires = [ "runner-image-load.service" ];
      after = [ "runner-image-load.service" "network-online.target" "run-jit.mount" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        TimeoutStartSec = "infinity";
        # The JIT blob is read by systemd from the read-only share and handed
        # to this unit alone; it is single-use and consumed before any job
        # step runs.
        LoadCredential = "jit:/run/jit/jit-config";
        # Power off on every path, including a failed credential load, so a
        # slot can never wedge holding memory.
        ExecStopPost = "${pkgs.systemd}/bin/systemctl poweroff --no-block";
      };
      script = ''
        set -u
        mkdir -p /var/cache/runner/gomod /var/cache/runner/gobuild \
                 /var/cache/runner/tool /var/cache/runner/tmp
        if jit="$(cat "$CREDENTIALS_DIRECTORY/jit" 2>/dev/null)" && [ -n "$jit" ]; then
          ${pkgs.podman}/bin/podman run --rm --name runner-job --user 0 \
            -e RUNNER_ALLOW_RUNASROOT=1 \
            -e GOMODCACHE=/var/cache/runner/gomod \
            -e GOCACHE=/var/cache/runner/gobuild \
            -e AGENT_TOOLSDIRECTORY=/var/cache/runner/tool \
            -e TMPDIR=/var/cache/runner/tmp \
            -v /var/cache/runner:/var/cache/runner \
            --entrypoint /home/runner/run.sh \
            ${cfg.runnerImageName} --jitconfig "$jit" || true
        fi
      '';
    };

    # Keep the guest minimal so the time to first job stays small.
    documentation.enable = false;
    systemd.services."getty@tty1".enable = false;
    services.openssh.enable = false;
    systemd.services.systemd-udev-settle.enable = false;
    systemd.services.NetworkManager-wait-online.enable = false;
  };
}
