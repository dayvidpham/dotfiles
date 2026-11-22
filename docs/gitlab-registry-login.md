# On-Demand GitLab Container Registry Login (`desktop`)

This setup provides a headless, on-demand login helper (`gitlab-registry-login`)
for publishing OCI images and SIF artifacts to
`registry.gitlab.com/dayvidpham/humanoid/sfurs-runtime` from `desktop`,
including after a reboot over SSH or inside `tmux`.

It uses the existing host `age` key and NixOS `sops-nix` (`/run/secrets`), and
is completely separate from the GPG keyring, `pass-secret-service`, PAM, and
D-Bus. No graphical session or `gpg-unlock` is required.

`flowX13` is intentionally excluded (not a recipient in `.sops.yaml` and the
module is not enabled there).

## First-Time Secret Provisioning

1. Copy the template and replace the placeholder with the real
   `dayvidpham-agent_bot` Personal Access Token (PAT):

   ```bash
   cp secrets/gitlab/secrets.yaml.example secrets/gitlab/secrets.yaml
   ```

   The exact YAML key required is:

   ```yaml
   gitlab_registry_humanoid_pat: <your-gitlab-pat>
   ```

2. Encrypt the file in place using the `.sops.yaml` rule for
   `secrets/gitlab/.*\.yaml$` (desktop host key + portable user key):

   ```bash
   sops -e -i secrets/gitlab/secrets.yaml
   ```

3. Stage the encrypted file so the Nix flake sees it, then activate NixOS:

   ```bash
   git add secrets/gitlab/secrets.yaml
   ./switch.sh nixos
   ```

Once activated, `sops-nix` decrypts `gitlab_registry_humanoid_pat` to:

```text
/run/secrets/gitlab/registry-pat
```

owned by `minttea` with mode `0400` on in-memory `ramfs`. No login is executed
during system activation.

## Usage

Run the explicit login command as `minttea` (works from a headless SSH session
or `tmux` right after reboot):

```bash
gitlab-registry-login
```

### Dedicated Auth File Path

`gitlab-registry-login` writes a dedicated auth file under `$XDG_RUNTIME_DIR`
with mode `0600` (inside a `0700` directory):

```text
$XDG_RUNTIME_DIR/gitlab-registry/auth.json
```

For `minttea` (UID `1000`), this resolves to:

```text
/run/user/1000/gitlab-registry/auth.json
```

Because it writes to a dedicated path (and unsets `REGISTRY_AUTH_FILE` and
`DOCKER_CONFIG` during login), it never overwrites
`$XDG_RUNTIME_DIR/containers/auth.json` or any other registry logins. The PAT
is streamed directly from `/run/secrets/gitlab/registry-pat` into
`podman login --password-stdin` and never appears in command arguments,
environment variables, logs, or the Nix store.

Because `$XDG_RUNTIME_DIR` lives in `tmpfs`, the auth file is cleared on reboot
and restored on demand by running `gitlab-registry-login`.

### Using with Podman (`--authfile`)

Verify the active login (read-only):

```bash
podman login \
  --authfile "$XDG_RUNTIME_DIR/gitlab-registry/auth.json" \
  --get-login registry.gitlab.com
# Expected output: dayvidpham-agent_bot
```

Pull or push an OCI image:

```bash
podman push \
  --authfile "$XDG_RUNTIME_DIR/gitlab-registry/auth.json" \
  registry.gitlab.com/dayvidpham/humanoid/sfurs-runtime:<tag>
```

### Using with ORAS (`--registry-config`)

Read-only verification against the existing `v35d-sif` tag (does not push or
delete anything):

```bash
oras manifest fetch \
  --registry-config "$XDG_RUNTIME_DIR/gitlab-registry/auth.json" \
  registry.gitlab.com/dayvidpham/humanoid/sfurs-runtime:v35d-sif
```

(If `oras` is not on your `PATH`, run it via `nix run nixpkgs#oras -- manifest fetch ...`.)

Push a SIF artifact:

```bash
oras push \
  --registry-config "$XDG_RUNTIME_DIR/gitlab-registry/auth.json" \
  registry.gitlab.com/dayvidpham/humanoid/sfurs-runtime:<tag> \
  <artifact.sif>:application/vnd.sylabs.sif.layer.v1.sif
```

## Rotating the PAT

1. Update `gitlab_registry_humanoid_pat` in the encrypted YAML file:

   ```bash
   sops secrets/gitlab/secrets.yaml
   ```

2. Activate the updated NixOS configuration so `sops-nix` refreshes
   `/run/secrets/gitlab/registry-pat`:

   ```bash
   git add secrets/gitlab/secrets.yaml
   ./switch.sh nixos
   ```

3. Re-run the login command to atomically refresh the runtime auth file:

   ```bash
   gitlab-registry-login
   ```

4. Re-verify (read-only):

   ```bash
   podman login \
     --authfile "$XDG_RUNTIME_DIR/gitlab-registry/auth.json" \
     --get-login registry.gitlab.com
   ```

## Error Handling

- **Missing secret file** (`/run/secrets/gitlab/registry-pat` absent): exits
  non-zero with setup instructions (create/encrypt `secrets/gitlab/secrets.yaml`,
  `git add`, `./switch.sh nixos`).
- **Empty or unreadable secret file**: exits non-zero without touching any auth
  file.
- **Wrong user** (not `minttea`): exits non-zero.
- **Registry login failure** (invalid/expired PAT or network error): reports
  the failure without printing the token, removes the temporary file, and
  leaves any previously valid auth file intact.
