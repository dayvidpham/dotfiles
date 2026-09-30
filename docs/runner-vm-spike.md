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

### GitHub App

No existing organization app fits. The installed apps are Renovate, Claude,
Cursor, Blacksmith, Railway, and the peasant-labs apps (gofetch, releaser,
reviewer, ui); none carries the self-hosted-runner or variables permissions,
and reusing one would either over-grant or entangle the dispatcher with other
automation. Create a dedicated, organization-owned app
(Settings → Developer settings → GitHub Apps → New GitHub App):

- **Name:** `peasant-labs-runner-dispatcher` (the scale set name is separate).
- **Webhook:** uncheck **Active**. The dispatcher polls; nothing calls back.
- **Repository permissions:** `Metadata: Read-only` (always on) and
  `Variables: Read and write` — the heartbeat is the repository variable
  `RUNNER_POOL_HEALTH` on `peasant-labs/infra`.
- **Organization permissions:** `Self-hosted runners: Read and write` —
  scale-set registration and JIT configs.
- Nothing else.

Then **Install App** on the organization with access to at least
`peasant-labs/infra` (all repositories is fine). Note the **App ID** (or Client
ID; the SDK accepts either) from the app page, and the **installation ID** from
the install URL
(`https://github.com/organizations/peasant-labs/settings/installations/<id>`).
Both can also be read back with:

```bash
gh api /orgs/peasant-labs/installations \
  --jq '.installations[] | select(.app_slug=="<app-slug>") | {app_id, id}'
```

Generate a private key on the app page (a `.pem` download) and store it in
sops. The `secrets/github-runner/` creation rule already lists the desktop and
user age keys, so only the value needs adding:

```bash
sops set --value-file secrets/github-runner/secrets.yaml \
  '["github_app_private_key"]' /path/to/<app>.private-key.pem
```

or `sops secrets/github-runner/secrets.yaml` and paste the PEM under
`github_app_private_key` (see `secrets.yaml.example`). Keep the original PEM:
the systemd-creds copy below is machine-bound, and so is the downloaded key —
GitHub only shows it once.

### Host

1. Merge the infra branch and update the input: `nix flake update infra` in
   the dotfiles repo.
2. Configure the host:

   ```nix
   sops.secrets."github-runner/app-key" = {
     sopsFile = ../../secrets/github-runner/secrets.yaml;
     key = "github_app_private_key";
     owner = "root";
     mode = "0400";
   };
   CUSTOM.virtualisation.runner-vm.enable = true;
   CUSTOM.services.runner-dispatcher = {
     enable = true;
     app = {
       clientId = "<app id or client id>";
       installationId = <installation id>;
       privateKeyFile = config.sops.secrets."github-runner/app-key".path;
     };
   };
   ```

3. Make sure the router token can read repository variables on
   `peasant-labs/infra` (otherwise the router falls back with
   `query-failed`).
4. Drain the container pool and rebuild (`./switch.sh` drains first).

The dispatcher's first start runs `runner-dispatcher-credential.service`, which
encrypts the PEM with systemd-creds into
`/var/lib/runner-dispatcher/app-private-key.cred`; the dispatcher reads only the
encrypted copy (`LoadCredentialEncrypted`) and cannot reach the plaintext
secret. To rotate the key, delete the `.cred` file, update sops, and rebuild.

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
