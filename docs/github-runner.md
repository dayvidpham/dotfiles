# GitHub Actions self-hosted runners (desktop)

Module: `modules/nixos/services/github-runner/`. Enabled in
`hosts/desktop/configuration.nix`. The runner user's registration PAT is the
sops secret `github-runner/token`; the routing jobs in the repositories use the
organization secret `RUNNER_STATUS_TOKEN` (read-only runner list).

## How it works

- Four ephemeral runners (`desktop-1..4`) in the organization runner group
  `minttea--desktop`, labels `self-hosted`, `linux`, `x64`, `nixos`, `podman`.
- Each runner handles one job, deregisters, and systemd registers a fresh
  instance. `restartIfChanged = false` keeps a `nixos-rebuild switch` from
  killing a running job; the update is picked up after the next job.
- Jobs use the runner user's rootless podman socket via `DOCKER_HOST`; the
  work directories are systemd state directories (created before the unit's
  mount namespace is set up).
- The routing probe lives in the infra repository
  (`.github/workflows/runner-routing-probe.yml`, `workflow_dispatch`).

## Hosted-parity quirks handled here

- `gnumake`, `binutils`: hosted images ship `make` and `ar`; jobs call them.
- `node20` runtime alias: nixpkgs ships the runner with `node24` only; some
  actions (for example `actions/cache`) resolve `externals/node20`.
- `ProtectProc = "default"`: the runner reads `/proc/1/cgroup` while
  initializing job service containers; `invisible` hides it.
- `ProtectHostname = false`: crun calls `sethostname(2)` in the container's
  UTS namespace; the seccomp filter blocks it.
- Sandbox relaxations for rootless podman: namespaces, setuid helpers,
  `ProtectHome`, device access.

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
  `nixos/modules/services/continuous-integration/github-runner/`).
