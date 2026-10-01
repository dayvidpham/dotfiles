# GitHub runner per-job microVM (guest side).
#
# Boots with the runner image already loaded, registers with a one-shot JIT
# config injected through a read-only virtiofs mount, runs exactly one job, and
# powers off. The shared cache directory is the only state that outlives the
# VM. Jobs get the guest's own podman socket for service and job containers.
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.CUSTOM.virtualisation.runner-vm.guest;

  # The runner install lives on the slot disk at this path, and the runner
  # container mounts it at the same path. Jobs ask the guest's podman to bind
  # workspace, temp and externals paths into sibling containers, and podman
  # resolves those paths on the guest, so both sides must agree. The path is
  # identical in every VM: the Go build cache keys on source directories, so a
  # per-slot path would cache every package once per slot.
  runnerRoot = "/var/lib/containers/runner";
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
    disksHostPath = mkOption {
      type = types.str;
      description = "Host directory holding this slot's container-store disk image.";
    };
    runnerImage = mkOption {
      type = types.package;
      description = "Docker-archive tarball loaded into podman at boot.";
    };
    runnerImageName = mkOption {
      type = types.str;
      description = "Repository:tag the image is loaded as.";
    };
    diskSize = mkOption {
      type = types.ints.positive;
      default = 16384;
      description = ''
        Maximum size in MiB of the slot's scratch disk. The file is sparse and
        trimmed at every boot, so the host holds only what the last job wrote.
        Applies when the image is created; delete an existing image to resize.
      '';
    };
    idleTimeoutSec = mkOption {
      type = types.ints.positive;
      default = 600;
      description = ''
        Seconds the runner may wait for its first job before the VM powers
        off. A cancelled assignment otherwise leaves a VM holding its memory
        forever, because the host cannot tell an idle runner from a busy one.
      '';
    };
  };

  config = {
    system.stateVersion = "25.11";
    networking.hostName = "runner-vm-${toString cfg.slot}";

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = cfg.vcpu;
      mem = cfg.mem;
      # AF_VSOCK enables the host unit's Type=notify: systemd in the guest
      # signals boot-readiness over vmm.notify_socket, so starting the unit
      # means the VM is actually usable, not just that the hypervisor was
      # exec'd. CIDs are host-unique; 0/1/2 are reserved.
      vsock.cid = 100 + cfg.slot;
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
      # Container storage, the runner install, the workspace and job temp
      # files live on this scratch volume, not the tmpfs root: the runner image
      # alone is ~1.4 GiB uncompressed and the root is half the guest's RAM.
      # Every boot wipes it and trims the freed blocks back to the host.
      volumes = [
        {
          image = "${cfg.disksHostPath}/runner-vm-${toString cfg.slot}.img";
          mountPoint = "/var/lib/containers";
          size = cfg.diskSize;
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

    # The shared cache and the read-only JIT directory are the only host paths
    # a job VM may see. A new share would expose host state to untrusted job
    # code, so adding one must be a deliberate change to this assertion.
    assertions = [
      {
        assertion = lib.sort lib.lessThan (map (s: s.tag) config.microvm.shares) == [ "cache" "jit" ];
        message = "runner-vm guest: only the 'cache' and 'jit' shares may reach a job VM, found: "
          + lib.concatMapStringsSep ", " (s: s.tag) config.microvm.shares;
      }
    ];

    # The guest kernel ships netfilter as loadable modules and nothing inside
    # the guest loads them on demand, unlike a normal NixOS host. Without
    # nf_tables/nft_nat/nft_masq loaded, netavark cannot program container
    # networking: published service ports are unreachable and bridge-network
    # containers have no egress. The container pool never saw this because its
    # host kernel autoloads the modules.
    boot.kernelModules = [
      "nf_tables"
      "nf_nat"
      "nft_nat"
      "nft_masq"
      "nft_chain_nat"
      "nft_compat"
    ];

    virtualisation.podman.enable = true;
    virtualisation.containers.enable = true;
    # The guest's own podman API, for services: and container: jobs. It runs
    # as guest root and controls only this VM's containers; the host's podman
    # socket never reaches a VM.
    systemd.sockets.podman.wantedBy = [ "sockets.target" ];

    # The runner image ships in the read-only Nix store; loading it costs a few
    # seconds per boot and removes every per-job registry pull.
    systemd.services.runner-image-load = {
      description = "Load the baked runner image into podman";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Podman's output goes to the guest console, which the host captures in
        # this machine's journal — a load failure is diagnosable from the host.
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        # A failure here means runner-job never starts (its dependency), so the
        # job unit's poweroff cannot fire. Power the guest off directly; a slot
        # must never wedge holding memory.
        OnFailure = [ "poweroff.target" ];
      };
      script = ''
        set -euo pipefail
        podman=${pkgs.podman}/bin/podman
        # The volume is scratch space; start from an empty store and runner
        # root so a slot never inherits a previous job's state.
        rm -rf /var/lib/containers/storage ${runnerRoot}
        # Hand the freed blocks back to the host so the sparse disk image only
        # holds what this job writes. Advisory: a failed trim costs host disk,
        # not correctness.
        ${pkgs.util-linux}/bin/fstrim -v /var/lib/containers || true
        "$podman" load -i ${cfg.runnerImage}
        # Copy the runner install out of the image to the shared-path runner
        # root (see runnerRoot).
        mnt="$("$podman" image mount ${cfg.runnerImageName})"
        cp -a "$mnt/home/runner" ${runnerRoot}
        "$podman" image unmount ${cfg.runnerImageName}
        mkdir -p ${runnerRoot}/tmp
      '';
    };

    # One job per VM: register with the injected JIT config, run, power off.
    systemd.services.runner-job = {
      description = "Run one GitHub Actions job and shut the VM down";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      requires = [ "runner-image-load.service" "podman.socket" ];
      after = [ "runner-image-load.service" "podman.socket" "network-online.target" "run-jit.mount" ];
      serviceConfig = {
        # exec, not oneshot: a oneshot wanted by multi-user holds boot
        # completion — and with it the host unit's Type=notify READY — until
        # the job finishes, so a start could never observe a ready VM. exec
        # reports started at spawn and the job keeps running.
        Type = "exec";
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
                 /var/cache/runner/tool
        if jit="$(cat "$CREDENTIALS_DIRECTORY/jit" 2>/dev/null)" && [ -n "$jit" ]; then
          # Host networking, like the container pool: the guest's resolver is
          # systemd-resolved's stub (127.0.0.53), which is unreachable from a
          # container's own network namespace, while the guest's DHCP/NAT path
          # already works.
          #
          # Temp files stay on the slot disk: the shared cache outlives the VM
          # and is visible to every later job, so nothing per-job belongs there.
          ${pkgs.podman}/bin/podman run --rm --name runner-job --user 0 \
            --network=host \
            -e RUNNER_ALLOW_RUNASROOT=1 \
            -e GOMODCACHE=/var/cache/runner/gomod \
            -e GOCACHE=/var/cache/runner/gobuild \
            -e AGENT_TOOLSDIRECTORY=/var/cache/runner/tool \
            -e TMPDIR=${runnerRoot}/tmp \
            -e DOCKER_HOST=unix:///var/run/docker.sock \
            -e CONTAINER_HOST=unix:///var/run/docker.sock \
            -v /var/cache/runner:/var/cache/runner \
            -v ${runnerRoot}:${runnerRoot} \
            -v /run/podman/podman.sock:/var/run/docker.sock \
            --entrypoint ${runnerRoot}/run.sh \
            ${cfg.runnerImageName} --jitconfig "$jit" || true
        fi
      '';
    };

    # A runner whose assignment was cancelled, or a VM booted as a replacement
    # for a job GitHub already failed, waits for work forever. The runner
    # writes a Worker log in its _diag directory when a job reaches it; with
    # none after the timeout, stop the job unit, whose stop path powers the VM
    # off.
    systemd.services.runner-idle-guard = {
      description = "Power off a runner VM that never receives a job";
      wantedBy = [ "runner-job.service" ];
      after = [ "runner-job.service" ];
      partOf = [ "runner-job.service" ];
      serviceConfig.Type = "exec";
      script = ''
        sleep ${toString cfg.idleTimeoutSec}
        if ! ls ${runnerRoot}/_diag/Worker_*.log >/dev/null 2>&1; then
          echo "no job started within ${toString cfg.idleTimeoutSec}s; stopping the runner"
          ${pkgs.systemd}/bin/systemctl stop runner-job.service
        fi
      '';
    };

    # Keep the guest minimal so the time to first job stays small.
    documentation.enable = false;
    systemd.services."getty@tty1".enable = false;
    services.openssh.enable = false;
    systemd.services.systemd-udev-settle.enable = false;
    systemd.services.NetworkManager-wait-online.enable = false;

    # The host captures this machine's serial console in the unit journal.
    # Forwarding the guest journal to the console is the only debugging channel
    # into a VM with no ssh, and it is what makes a wedged job diagnosable from
    # the host.
    services.journald.extraConfig = "ForwardToConsole=yes";
  };
}
