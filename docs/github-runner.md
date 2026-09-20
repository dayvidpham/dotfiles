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
  `container/Containerfile` (digest-pinned Ubuntu 26.04 + actions/runner +
  build-essential + docker CLI + gh + podman; apt installs from a dated
  archive snapshot; both downloaded tarballs SHA-256 verified) and tagged
  `localhost/peasant-github-runner:<runner
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
  `--network=host` keeps published ports reachable. The socket already belongs
  to the host user, which is the agent's host identity, so no ACL is needed.
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
  `github-runner-image` (pulls and verifies the pinned image), `github-runner-prepare` (directories and
  state ownership), `github-runner-container@<instance>` (one `podman run` in the
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

## Pin freshness and checksums

`container/Containerfile` pins every build input: the Ubuntu base digest, the
dated archive snapshot the apt versions resolve from, the exact apt versions,
and the two downloaded tarballs with their SHA-256 digests. The build verifies
each download with `sha256sum -c` and fails closed on a mismatch.

`renovate.json5` (repo root) asks Renovate to track the pins that have an
upstream feed:

- the `ubuntu:26.04` digest — digest updates only; a release-line change
  re-resolves the apt snapshot and version set, so it stays deliberate;
- `RUNNER_VERSION` — `actions/runner` GitHub releases;
- `DOCKER_VERSION` — the static-tarball directory listing.

The pins come as one grouped PR ("runner image pins"). Renovate only moves
versions; the matching `*_SHA256` args (and, for a base change,
`UBUNTU_SNAPSHOT` plus the apt version list) must move in the same change, as
the PR note says. `UBUNTU_SNAPSHOT` itself has no upstream index — the
snapshot service accepts any timestamp after 2023-03-01 and publishes no
listing — so Renovate never proposes it; bump it by hand together with the
digest and the apt pins.

Recompute a digest manually when bumping a version:

```sh
# actions/runner (the release asset digest is also visible in the GitHub API)
curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | sha256sum

# docker CLI static tarball (Docker publishes no checksum file for it)
curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" | sha256sum
```

Renovate must be enabled for this repository (the Mend Renovate app, or a
self-hosted run against `renovate.json5`) before it can open update PRs.

## Publishing the runner image

The module does not build the image. It pulls
`quay.io/peasant-labs/github-runner@sha256:…`, verifies the image's Sigstore
signature against the publishing workflow's identity, and only then starts
containers. The Containerfile stays in the repository as the recipe.

Publishing runs in GitHub Actions: **Actions → Runner image → Run workflow**.
The workflow builds the Containerfile, pushes
`quay.io/peasant-labs/github-runner:<RUNNER_VERSION>`, and keylessly signs the
stored digest with cosign. The signature names
`https://github.com/dayvidpham/dotfiles/.github/workflows/runner-image.yml@refs/heads/main`
and is recorded in the Sigstore transparency log. It authenticates to Quay with
the `QUAY_ROBOT_TOKEN` repository secret (the `peasant-labs+builder` robot,
write on the `github-runner` repository).

Copy the digest from the run summary into `imageRef` in `default.nix`.

Two Quay quirks the workflow already handles, and that any manual publish must
respect:

- Quay re-serializes the manifest per `Accept` media type, and the converted
  form is not addressable by digest. Resolve the digest from the served
  manifest bytes and require the registry to resolve that digest before
  signing; do not trust the `Docker-Content-Digest` header or a client-side
  `RepoDigests` value alone.
- A tag push is not a re-publish; the digest changes with every build, so pin
  the new digest rather than reusing an old one.

The module records the verified reference in a stamp file, so a reboot needs
neither the registry nor Sigstore.

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
