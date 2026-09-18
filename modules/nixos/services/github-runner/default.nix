{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.github-runner;

  inherit (lib)
    concatMapStringsSep
    escapeShellArg
    genAttrs
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  podman = "${config.virtualisation.podman.package}/bin/podman";

  # Identity model: every writer in a runner's cgroup tree is the host user.
  # The runner container runs as its userns root (container uid 0 -> the host
  # user), and root inside job containers plus `sudo` in the runner container
  # map the same way, because they all share this user's user namespace. A
  # directory written by any of them is therefore owned by the host user and
  # can be cleaned by the others. Running the runner as a non-root container
  # user (for example uid 1001) maps it onto a subuid instead and splits the
  # workspace between two writers that cannot clean up after each other. The
  # de-facto standard runner images run the agent as root for the same reason.
  #
  # Rootless podman still needs the user's subuid/subgid ranges for the job
  # containers' own user namespaces; the assertion below keeps that true.

  # Each runner lives in its own systemd slice so its cgroup tree (the runner
  # container and the job processes inside it) can carry resource limits. The
  # slice name is index-based to keep the implicit slice hierarchy shallow:
  # systemd nests `a-b-c.slice` under `a-b.slice` under `a.slice`.
  instances = map (i: {
    name = "${cfg.name}-${toString i}";
    slice = "github-runner-${toString i}";
  }) (lib.range 1 cfg.count);

  instanceNames = map (instance: instance.name) instances;

  # systemd slice settings for one resource tier; null options are dropped so
  # the slice keeps systemd's default for that knob.
  mkSliceConfig = tier: lib.filterAttrs (_: value: value != null) {
    MemoryMax = tier.memoryMax;
    MemoryHigh = tier.memoryHigh;
    CPUQuota = tier.cpuQuota;
    CPUWeight = tier.cpuWeight;
    TasksMax = tier.tasksMax;
  };

  containerDir = ./container;
  containerfile = "${containerDir}/Containerfile";
  entrypoint = "${containerDir}/entrypoint.sh";

  imageTag = "localhost/peasant-github-runner:${cfg.runnerVersion}";

  imageHash = builtins.substring 0 12 (builtins.hashString "sha256"
    (builtins.readFile containerfile + builtins.readFile entrypoint));

  mkPodmanRunArgs = instance: slice: [
    "run" "--rm"
    # --replace removes a leftover container with the same name after a crash.
    "--replace"
    "--name" "github-runner-${instance}"
    # Run the agent as the userns root (the host user). See the identity-model
    # comment above: this is what keeps the workspace single-owner. The runner
    # refuses to configure or start as root without this acknowledgement.
    "--user" "0"
    "-e" "RUNNER_ALLOW_RUNASROOT=1"
    # Keep the container payload inside the runner's own systemd slice so the
    # slice's MemoryMax/CPUQuota apply to the jobs, not just to the CLI.
    "--cgroup-parent=${slice}.slice"
    "--network=host"
    # The whole state tree is mounted at its host path so sibling containers
    # started by jobs can bind mount workspace paths by identical path.
    "-v" "${cfg.stateDir}:${cfg.stateDir}"
    "-e" "DOCKER_HOST=unix:///var/run/docker.sock"
    "-e" "CONTAINER_HOST=unix:///var/run/docker.sock"
    "-e" "GITHUB_RUNNER_URL=${cfg.url}"
    "-e" "GITHUB_RUNNER_NAME=${instance}"
    "-e" "GITHUB_RUNNER_GROUP=${lib.optionalString (cfg.runnerGroup != null) cfg.runnerGroup}"
    "-e" "GITHUB_RUNNER_LABELS=${lib.concatStringsSep "," cfg.labels}"
    "-e" "GITHUB_RUNNER_EPHEMERAL=${if cfg.ephemeral then "1" else "0"}"
    # Fallback path for the PAT when the host user cannot read it under this
    # user's ownership; the primary path passes it through the environment.
    "-v" "${cfg.tokenFile}:/run/github-runner/token:ro"
    "-e" "RUNNER_ROOT=${cfg.stateDir}/runners/${instance}"
    "-e" "RUNNER_WORK=${cfg.stateDir}/work/${instance}"
    "-e" "TMPDIR=${cfg.stateDir}/work/${instance}/tmp"
    "-e" "AGENT_TOOLSDIRECTORY=${cfg.stateDir}/cache/_tool"
    "-e" "GOMODCACHE=${cfg.stateDir}/cache/gomod"
    "-e" "GOCACHE=${cfg.stateDir}/cache/gobuild"
  ];

  # The PAT is read by the host user (the module's sops secret is readable
  # there) and handed to the container through its environment, so the
  # container user never needs read access to the secret file. The entrypoint
  # unsets it before the listener starts, so job steps cannot inherit it.
  # The podman socket is resolved when the script runs: systemd specifiers
  # (%t) only expand in the unit's ExecStart line, not inside a script body.
  mkRunScript = instance: slice: pkgs.writeShellScript "github-runner-run-${instance}" ''
    set -euo pipefail
    runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    socket="$runtime/podman/podman.sock"
    token="$(cat ${cfg.tokenFile})"
    exec ${podman} ${lib.escapeShellArgs (mkPodmanRunArgs instance slice)} \
      --volume "$socket:/var/run/docker.sock" \
      --env "GITHUB_RUNNER_TOKEN=$token" ${imageTag}
  '';

  buildImage = pkgs.writeShellScript "github-runner-build-image" ''
    set -euo pipefail
    mkdir -p ${escapeShellArg cfg.stateDir}
    stamp=${escapeShellArg "${cfg.stateDir}/.image-stamp"}
    hash=${escapeShellArg imageHash}
    if ${podman} image exists ${escapeShellArg imageTag} \
      && [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$hash" ]; then
      exit 0
    fi
    ${podman} build --tag ${escapeShellArg imageTag} \
      --file ${containerfile} ${containerDir}
    printf '%s' "$hash" > "$stamp"
  '';

  prepareState = pkgs.writeShellScript "github-runner-prepare-state" ''
    set -euo pipefail
    ${concatMapStringsSep "\n" (instance: ''
      mkdir -p ${escapeShellArg cfg.stateDir}/runners/${instance} \
               ${escapeShellArg cfg.stateDir}/work/${instance}/tmp
    '') instanceNames}
    mkdir -p ${escapeShellArg cfg.stateDir}/cache
    # One owner for the whole tree: the host user. The runner container runs as
    # the userns root (host user) and job containers' root and `sudo` map the
    # same way, so nothing here needs a subuid mapping or a socket ACL.
    ${concatMapStringsSep "\n" (instance: ''
      ${podman} unshare chown -R 0:0 \
        ${escapeShellArg cfg.stateDir}/runners/${instance} \
        ${escapeShellArg cfg.stateDir}/work/${instance}
    '') instanceNames}
    ${podman} unshare chown -R 0:0 ${escapeShellArg cfg.stateDir}/cache
  '';
in
{
  options.CUSTOM.services.github-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner containers (rootless podman)";

    url = mkOption {
      type = types.str;
      default = "https://github.com/peasant-labs";
      description = "GitHub organization URL the runners register against";
    };

    name = mkOption {
      type = types.str;
      default = "${config.networking.hostName}-container";
      description = "Base runner name; instances are suffixed -1..count";
    };

    count = mkOption {
      type = types.int;
      default = 1;
      description = "Runner containers to run; each handles one job at a time";
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [ "container" ];
      description = "Extra labels on top of the default self-hosted/linux/x64 labels";
    };

    runnerGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Organization runner group. Must already exist in GitHub before the
        containers start, otherwise registration fails.
      '';
    };

    tokenFile = mkOption {
      type = types.path;
      description = ''
        File holding a fine-grained PAT with organization "Self-hosted
        runners: Read and write" permission (or a classic admin:org PAT).
        Must be readable by {option}`user`.
      '';
      example = "/run/secrets/github-runner/token";
    };

    resources = {
      pool = {
        memoryMax = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "48G";
          description = ''
            `MemoryMax` for the pool's parent slice (`github-runner.slice`),
            the ceiling for all runners together; `null` leaves it unlimited.
          '';
        };

        memoryHigh = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "40G";
          description = ''
            `MemoryHigh` soft limit for the pool's parent slice: the kernel
            reclaims and throttles before the hard {option}`resources.pool.memoryMax`
            kill; `null` leaves it unset.
          '';
        };

        cpuQuota = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "2400%";
          description = ''
            `CPUQuota` for the pool's parent slice (100% is one core): a hard
            bandwidth ceiling that reserves headroom for the rest of the
            machine; `null` leaves it unlimited.
          '';
        };

        cpuWeight = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 100;
          description = ''
            `CPUWeight` for the pool's parent slice, its relative share against
            the rest of the user session when CPU is contended (systemd default
            100); `null` leaves it at the default.
          '';
        };

        tasksMax = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 16384;
          description = ''
            `TasksMax` for the pool's parent slice; `null` leaves it at
            systemd's default.
          '';
        };
      };

      runner = {
        memoryMax = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "12G";
          description = ''
            `MemoryMax` for each runner's systemd slice. The runner container
            and the job processes inside it run under this limit; `null`
            leaves it unlimited. Containers that jobs start through the podman
            socket (service containers, `docker run` steps, job containers)
            are separate scopes and are NOT covered.
          '';
        };

        memoryHigh = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "10G";
          description = ''
            `MemoryHigh` soft limit per runner slice: reclaim pressure before
            the hard {option}`resources.runner.memoryMax` kill; `null` leaves
            it unset.
          '';
        };

        cpuQuota = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "800%";
          description = ''
            `CPUQuota` hard bandwidth cap per runner slice (100% is one core).
            Prefer {option}`resources.runner.cpuWeight` for CI: a quota caps
            throughput even when the machine is idle.
          '';
        };

        cpuWeight = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 100;
          description = ''
            `CPUWeight` per runner slice: equal weights divide the pool's CPU
            fairly under contention while a lone runner can still burst across
            idle cores; `null` leaves it at systemd's default (100).
          '';
        };

        tasksMax = mkOption {
          type = types.nullOr types.int;
          default = null;
          example = 4096;
          description = ''
            `TasksMax` for each runner's systemd slice (process/thread cap);
            `null` leaves it at systemd's default.
          '';
        };
      };
    };

    ephemeral = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Register per job and wipe runner state afterwards. Ephemeral runners
        re-register through the PAT before every job.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "minttea";
      description = "Host user whose rootless podman runs the containers and owns the state tree";
    };

    stateDir = mkOption {
      type = types.str;
      default = "/home/${cfg.user}/.local/share/github-runner-containers";
      description = ''
        Host directory holding the runner install copies, workspaces and
        shared caches. It is mounted into the containers at the same path so
        sibling containers can bind mount workspace paths.
      '';
    };

    runnerVersion = mkOption {
      type = types.str;
      default = "2.337.0";
      description = "actions/runner release to bake into the image";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.users.users.${cfg.user}.subUidRanges != [ ];
        message = "CUSTOM.services.github-runner.user must have subuid ranges for rootless podman";
      }
    ];

    CUSTOM.virtualisation.podman.enable = true;

    systemd.user.services = {
      # Image build: podman builds from the module's Containerfile, guarded by
      # a content stamp so a rebuild only happens when the inputs change.
      github-runner-image = {
        description = "Build the GitHub Actions runner container image";
        after = [ "podman.socket" ];
        requires = [ "podman.socket" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = buildImage;
        };
        wantedBy = [ "default.target" ];
      };

      # Shared directories and the podman socket ACL the containers need.
      github-runner-prepare = {
        description = "Prepare GitHub Actions runner container state";
        after = [ "podman.socket" ];
        requires = [ "podman.socket" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = prepareState;
        };
        wantedBy = [ "default.target" ];
      };

      # One container per instance. Each instance gets its own unit (NixOS
      # writes every systemd.user.services attribute as a unit file; a
      # separate template attribute does not supply ExecStart to them). The
      # unit runs `podman run` in the foreground so systemd owns the
      # lifecycle; the entrypoint registers on first start (or when the PAT
      # rotates) and then launches the listener.
    } // lib.listToAttrs (map (instance: {
      name = "github-runner-container@${instance.name}";
      value = {
        description = "GitHub Actions runner container ${instance.name}";
        after = [ "github-runner-image.service" "github-runner-prepare.service" ];
        requires = [ "github-runner-image.service" "github-runner-prepare.service" ];
        serviceConfig = {
          Slice = "${instance.slice}.slice";
          ExecStart = mkRunScript instance.name instance.slice;
          ExecStop = "${podman} stop --time 60 github-runner-${instance.name}";
          TimeoutStopSec = 90;
          Restart = if cfg.ephemeral then "on-success" else "always";
          RestartSec = 5;
        };
        wantedBy = [ "default.target" ];
      };
    }) instances);

    # One resource slice per runner, all nested under the explicit
    # github-runner.slice pool group. The runner unit and its container payload
    # live inside the runner slice, so MemoryMax/CPUQuota/TasksMax bound what
    # jobs can use; the pool slice bounds all runners together.
    systemd.user.slices = {
      github-runner = {
        description = "GitHub Actions runner pool resource slice";
        sliceConfig = mkSliceConfig cfg.resources.pool;
      };
    } // lib.genAttrs (map (instance: instance.slice) instances) (slice: {
      description = "GitHub Actions runner resource slice ${slice}";
      sliceConfig = mkSliceConfig cfg.resources.runner;
    });
  };
}
