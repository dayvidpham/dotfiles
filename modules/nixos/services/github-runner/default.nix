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

  # The image's runner user is uid 1001 (Ubuntu's first user occupies 1000), and
  # rootless podman maps it onto the host user's subuid range:
  #   host uid = subUidStart + runnerUid - 1
  # `podman unshare chown` takes the in-container uid; the podman socket ACL
  # needs the host uid.
  runnerUid = 1001;
  subUidStart = (lib.head config.users.users.${cfg.user}.subUidRanges).startUid;
  runnerHostUid = subUidStart + runnerUid - 1;

  instanceNames = map (i: "${cfg.name}-${toString i}") (lib.range 1 cfg.count);

  containerDir = ./container;
  containerfile = "${containerDir}/Containerfile";
  entrypoint = "${containerDir}/entrypoint.sh";

  imageTag = "localhost/peasant-github-runner:${cfg.runnerVersion}";

  imageHash = builtins.substring 0 12 (builtins.hashString "sha256"
    (builtins.readFile containerfile + builtins.readFile entrypoint));

  # %t is the user manager's runtime directory (/run/user/<uid>), so the
  # container always mounts the podman socket of the user running it.
  socketPath = "%t/podman/podman.sock";

  mkPodmanRunArgs = instance: [
    "run" "--rm"
    # --replace removes a leftover container with the same name after a crash.
    "--replace"
    "--name" "github-runner-${instance}"
    "--network=host"
    # The whole state tree is mounted at its host path so sibling containers
    # started by jobs can bind mount workspace paths by identical path.
    "-v" "${cfg.stateDir}:${cfg.stateDir}"
    "-v" "${socketPath}:/var/run/docker.sock"
    "-e" "DOCKER_HOST=unix:///var/run/docker.sock"
    "-e" "CONTAINER_HOST=unix:///var/run/docker.sock"
    "-e" "GITHUB_RUNNER_URL=${cfg.url}"
    "-e" "GITHUB_RUNNER_NAME=${instance}"
    "-e" "GITHUB_RUNNER_TOKEN_FILE=/run/github-runner/token"
    "-e" "GITHUB_RUNNER_GROUP=${lib.optionalString (cfg.runnerGroup != null) cfg.runnerGroup}"
    "-e" "GITHUB_RUNNER_LABELS=${lib.concatStringsSep "," cfg.labels}"
    "-e" "GITHUB_RUNNER_EPHEMERAL=${if cfg.ephemeral then "1" else "0"}"
    "-v" "${cfg.tokenFile}:/run/github-runner/token:ro"
    "-e" "RUNNER_ROOT=${cfg.stateDir}/runners/${instance}"
    "-e" "RUNNER_WORK=${cfg.stateDir}/work/${instance}"
    "-e" "TMPDIR=${cfg.stateDir}/work/${instance}/tmp"
    "-e" "AGENT_TOOLSDIRECTORY=${cfg.stateDir}/cache/_tool"
    "-e" "GOMODCACHE=${cfg.stateDir}/cache/gomod"
    "-e" "GOCACHE=${cfg.stateDir}/cache/gobuild"
    "${imageTag}"
  ];

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
    runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    socket="$runtime/podman/podman.sock"
    ${concatMapStringsSep "\n" (instance: ''
      mkdir -p ${escapeShellArg cfg.stateDir}/runners/${instance} \
               ${escapeShellArg cfg.stateDir}/work/${instance}/tmp
    '') instanceNames}
    mkdir -p ${escapeShellArg cfg.stateDir}/cache
    # The shared root stays with the host user; each runner subtree belongs to
    # the in-container runner user's host-mapped uid.
    ${podman} unshare chown 0:0 ${escapeShellArg cfg.stateDir}
    ${concatMapStringsSep "\n" (instance: ''
      ${podman} unshare chown -R ${toString runnerUid}:${toString runnerUid} \
        ${escapeShellArg cfg.stateDir}/runners/${instance} \
        ${escapeShellArg cfg.stateDir}/work/${instance}
    '') instanceNames}
    ${podman} unshare chown -R ${toString runnerUid}:${toString runnerUid} \
      ${escapeShellArg cfg.stateDir}/cache
    if [ ! -S "$socket" ]; then
      echo "github-runner: $socket is not present; is the podman user socket running?" >&2
      exit 1
    fi
    ${pkgs.acl}/bin/setfacl -m u:${toString runnerHostUid}:rw "$socket"
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
      name = "github-runner-container@${instance}";
      value = {
        description = "GitHub Actions runner container ${instance}";
        after = [ "github-runner-image.service" "github-runner-prepare.service" ];
        requires = [ "github-runner-image.service" "github-runner-prepare.service" ];
        serviceConfig = {
          ExecStart = "${podman} ${lib.escapeShellArgs (mkPodmanRunArgs instance)}";
          ExecStop = "${podman} stop --time 60 github-runner-${instance}";
          TimeoutStopSec = 90;
          Restart = if cfg.ephemeral then "on-success" else "always";
          RestartSec = 5;
        };
        wantedBy = [ "default.target" ];
      };
    }) instanceNames);
  };
}
