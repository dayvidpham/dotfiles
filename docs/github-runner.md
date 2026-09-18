# GitHub Actions self-hosted runners (desktop)

Module: `modules/nixos/services/github-runner/`. Enabled in
`hosts/desktop/configuration.nix`. The runner registration PAT is the sops
secret `github-runner/token` (owned by `minttea`); the routing jobs in the
repositories use the organization secret `RUNNER_STATUS_TOKEN` (read-only
runner list).

## How it works

- Four **rootless podman containers** (`desktop-container-1..4`) in the
  organization runner group `minttea--desktop`, labels `self-hosted`, `linux`,
  `x64`, `container`. The image is built from
  `container/Containerfile` (Ubuntu 24.04 + actions/runner + build-essential +
  docker CLI + gh + podman) and tagged `localhost/peasant-github-runner:<runner
  version>`. A content stamp skips the rebuild when nothing changed.
- The module's state tree (`stateDir`, default
  `~/.local/share/github-runner-containers`) is mounted into every container at
  the same path it has on the host, and holds three subtrees:
  - `runners/<name>` — the runner install copy, credentials, `_diag`;
  - `work/<name>` — `_work`, `_temp`, `_actions`, and `TMPDIR`;
  - `cache` — shared toolchain (`AGENT_TOOLSDIRECTORY`), `GOMODCACHE`,
    `GOCACHE`.
  Path identity is what lets a job's **sibling containers** bind mount
  workspace paths: service containers, `docker run` steps, `container:` jobs
  (e.g. the AUR makepkg job), and the release e2e distro stacks all resolve
  their mounts on the host.
- The runner container mounts the host user's podman socket at
  `/var/run/docker.sock` (`DOCKER_HOST` and `CONTAINER_HOST` both point there)
  so the docker CLI tail the runner shells out to talks to the host engine.
  `--network=host` keeps published ports reachable.
- **Single-owner workspaces:** the agent runs as the container's root
  (`--user 0` with `RUNNER_ALLOW_RUNASROOT=1`), which under rootless podman maps
  to the host user — the same identity that root inside job containers and
  `sudo` in the runner container map to. Every writer in the runner's cgroup
  tree therefore owns the same files, so a job can always clean up what an
  earlier step or sibling container wrote. Running the agent as a non-root
  container user instead (for example the image's uid 1001) maps it onto a
  subuid, which splits the workspace between two identities that cannot clean
  up after each other (`dist/` removal fails with EACCES). Container root here
  has no host privilege: the userns maps only the host user and their subuids,
  and the container holds no capabilities.
- Registration uses `config.sh --pat` with the sops PAT; the entrypoint
  re-registers with `--replace` when the PAT rotates (stamp file in the runner
  root). `ephemeral = true` switches to per-job registration.
- Lifecycle is systemd user services for `minttea`:
  `github-runner-image` (build), `github-runner-prepare` (directories + socket
  ACL), `github-runner-container@<instance>` (one `podman run` in the
  foreground per runner). The user has linger enabled, so the pool comes back
  after a reboot and a `nixos-rebuild switch` restarts only what changed.
- **Resource isolation:** each runner has its own `github-runner-<n>.slice`
  nested under the explicit `github-runner.slice` pool group. The pool slice is
  the host-protection ceiling (hard `MemoryMax` with a soft `MemoryHigh`, and a
  `CPUQuota` that reserves cores for the desktop); each runner slice is the
  sibling fence (hard `MemoryMax`/`MemoryHigh` plus equal `CPUWeight`s, so a
  lone runner can burst across the pool's idle cores). Limits come from
  `resources.pool` and `resources.runner`. The service unit sets `Slice=` and
  the wrapper passes `--cgroup-parent=github-runner-<n>.slice`, so the runner
  container and the job processes inside it are bounded. Job-created
  containers (service containers, `docker run` steps, job containers, e2e
  distro stacks) are created through the host podman socket and land in their
  own scopes under `user.slice`, so they are **not** covered by these limits.
  Changing a limit takes effect after `systemctl --user daemon-reload` (the
  switch writes the slice unit files; the running user manager applies the
  changed resource settings on reload) or a reboot.

## Hosted-parity notes

The container image is Ubuntu, so the pool looks like a GitHub-hosted runner to
jobs: `gcc`/`CGO_ENABLED=1` by default, apt available, node available to
`setup-node`, no NixOS quirks (no `ProtectProc`, `ProtectHostname`, `node20`
alias, or `make`/`ar` shims needed — those were host-native concerns).

Known gaps:

- **No Nix** inside the pool. Jobs that need `nix develop` (for example
  Peasant's harvester version guard) stay on their previous runners until the
  image grows Nix or those jobs get a container-native toolchain.
- **Job containers cannot use the podman socket**: the runner passes
  `-v /var/run/docker.sock:/var/run/docker.sock` to job containers, and that
  host path does not exist for a sibling container. Jobs that need Docker
  inside a `container:` job would need the socket bind adjusted at the host
  path.

## Reference configurations

Working NixOS runner setups consulted while building this module:

- `ocf/nix` — `modules/github-actions/default.nix`: one container per runner,
  ephemeral, `restartIfChanged = false`; source of that pattern here.
- `dustinlyons/nixos-config` — `modules/nixos/github-runner.nix`: docker-based
  runners split into `ci` and `deploy` label pools to reserve capacity for
  deploys; useful if the pool ever needs reserved slots.
- `juspay/github-nix-ci` — `nix/module.nix`.
- `bbigras/nix-config` — `modules/nixos/services/github-runner.nix`.
- `bitcoin-dev-tools/nix-github-runner` — full deployment with sops-managed
  registration tokens.
- NixOS manual: `services.github-runners` options (nixpkgs
  `nixos/modules/services/continuous-integration/github-runner/`) — the
  host-native implementation this module used before the containers.
