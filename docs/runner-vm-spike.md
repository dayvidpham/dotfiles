# Runner pool spike: per-job Cloud Hypervisor VMs

Status: **spike, disabled by default.** The container pool keeps running until
this path is proven; both options default to `false`.

The spike replaces the fixed container pool's dispatch model with GitHub runner
scale sets: a host dispatcher long-polls the scale-set queue, and every assigned
job gets one fresh Cloud Hypervisor VM that runs exactly one job and powers off.
The router stops probing for online runners and reads a pool-health heartbeat
instead, because a scale set has no registered runners while idle.

## Pieces

| Piece | Where | What it does |
|---|---|---|
| Dispatcher | `infra` package `runner-dispatcher`, module `nixosModules.runner-dispatcher` | Scale-set session, JIT minting, systemd slot control, heartbeat |
| VM slots | dotfiles `modules/nixos/virtualisation/runner-vm` | Four CH slots, bridge + NAT, read-only JIT share, shared cache |
| Router | `infra` `.github/workflows/runner-router.yml` | Reads `RUNNER_POOL_HEALTH`; `pool-online` / `pool-stale` / `query-failed` |

## Enabling

1. Merge the infra branch and update the input:
   `nix flake update infra` in the dotfiles repo.
2. Create a GitHub App on the organization with **Actions: read and write**
   (scale sets, JIT configs) and **Variables: read and write** (heartbeat),
   install it, and store the PEM as a sops secret owned by root, mode 0400
   (for example `github-runner/app-key`).
3. Configure the host:

   ```nix
   sops.secrets."github-runner/app-key" = {
     sopsFile = ...;
     owner = "root";
     mode = "0400";
   };
   CUSTOM.virtualisation.runner-vm.enable = true;
   CUSTOM.services.runner-dispatcher = {
     enable = true;
     app = {
       clientId = "<app client id>";
       installationId = 0;
       privateKeyFile = config.sops.secrets."github-runner/app-key".path;
     };
   };
   ```

4. Make sure the router token can read repository variables on
   `peasant-labs/infra` (otherwise the router falls back with
   `query-failed`).
5. Drain the container pool and rebuild (`./switch.sh` drains first).

The dispatcher's first start provisions the systemd-creds encrypted copy of the
App key (`/var/lib/runner-dispatcher/app-private-key.cred`). Reinstalling the
host requires the original PEM again; the encrypted blob is machine-bound.

## Verifying

- **Boot smoke:** `systemctl start microvm@runner-vm-1` with no JIT config; the
  guest should boot, fail to load the credential, and power itself off. Check
  `journalctl -u microvm@runner-vm-1`.
- **End to end:** dispatch a trivial workflow with `runs-on: desktop-microvm`.
  Watch `systemctl status microvm@runner-vm-N` and the dispatcher journal
  (`journalctl -u runner-dispatcher`) for assignment-to-boot time; the VM is
  gone once the job finishes.
- **Heartbeat:** `gh api repos/peasant-labs/infra/actions/variables/RUNNER_POOL_HEALTH --jq .value`
  should show a fresh timestamp and `listener_healthy: true`.
- **Router:** a caller run (or the router smoke workflow) should report
  `pool-online` while the heartbeat is fresh, `pool-stale` after stopping the
  dispatcher.

## Rollback

Set `CUSTOM.virtualisation.runner-vm.enable = false` and
`CUSTOM.services.runner-dispatcher.enable = false`, then rebuild. The container
pool is untouched throughout; running slots finish their job and power off.

## Notes

- The JIT config is single-use and consumed before any job step runs; the guest
  never receives the App key.
- The cache share (`/var/lib/runner-vm/cache`) is writable by every slot; a
  malicious job can poison caches for later jobs (accepted, same as the
  container pool's shared caches).
- The router's heartbeat record is a repository variable in
  `peasant-labs/infra`; `query-failed` is the safe fallback when the token
  cannot read it.
