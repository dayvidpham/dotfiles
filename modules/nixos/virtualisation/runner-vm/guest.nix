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
      # Container storage lives on its own ext4 volume, not the tmpfs root:
      # the runner image is ~1.4 GiB uncompressed and overlay-on-tmpfs cannot
      # hold it inside the guest's 50%-of-RAM root. The volume is scratch
      # space; the image is loaded into a fresh store on every boot.
      volumes = [
        {
          image = "${cfg.disksHostPath}/runner-vm-${toString cfg.slot}.img";
          mountPoint = "/var/lib/containers";
          size = 6144;
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
        # The volume is scratch space; start from an empty store so a slot
        # never inherits a previous job's state.
        rm -rf /var/lib/containers/storage
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

    # The host captures this machine's serial console in the unit journal.
    # Forwarding the guest journal to the console is the only debugging channel
    # into a VM with no ssh, and it is what makes a wedged job diagnosable from
    # the host.
    services.journald.extraConfig = "ForwardToConsole=yes";
  };
}
