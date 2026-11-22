---
name: secrets-keyring-management
description: >-
  Work on this repo's Secret Service, GPG agent, pinentry-tmux, and PAM
  auto-unlock stack: pass-secret-service (disk-synced across physical niri and
  remote-session private D-Bus), gpg-agent (/etc/gnupg/gpg-agent.conf),
  scrypt + sops-nix PAM unlock on greetd/swaylock, and gpg-unlock. Use when
  debugging hangs in git commit/gpg/Secret Service, rotating the Linux or GPG
  passphrase, adding keygrips, or modifying keyring/pinentry config.
---

# Secrets & Keyring Management

## Architecture

This repo replaces `gnome-keyring-daemon` + `gcr-prompter` with a single GPG-rooted stack that works across all four session modes (physical `niri`, Moonlight/VNC `remote-session-compositor`, both simultaneously, and headless `tmux-server`):

```text
Secret Service apps (Chrome, Brave, Discord, gh, glab, entire-cli, antigravity)
  ├─ physical niri D-Bus (/run/user/1000/bus) ──► pass_secret_service (systemd user)
  └─ remote-session private D-Bus             ──► pass_secret_service (D-Bus activated)
                                                       │
                          both sync ~/.password-store/secret_service on disk
                                                       │
                                                       ▼
                           gpg-agent (/run/user/1000/gnupg/S.gpg-agent)
                             ├─ PAM auto-unlock: greetd / swaylock (pam_exec expose_authtok)
                             │    └─ scrypt dec -P /run/secrets/gpg/passphrase.scrypt
                             │         └─ libexec/gpg-preset-passphrase (SC + E keygrips)
                             ├─ Manual unlock (SSH / post-rebuild): `gpg-unlock`
                             └─ Fallback prompt: packages/pinentry-tmux
                                  ├─ TUI pane or empty GPG_TTY + attached client ─► newest active tmux client popup
                                  ├─ Non-tmux graphical terminal                 ─► pinentry-qt on requester's display
                                  └─ Empty GPG_TTY + no tmux client              ─► pinentry-qt (niri, else /run/user/<uid>/remote/wayland-1)
```

### Why `gnome-keyring-daemon` + `gcr-prompter` was replaced
1. `gcr-prompter` is a GTK3 binary D-Bus-activated by `systemd --user`; if an unlock is triggered when `niri` isn't running, it dies with `cannot open display:` and permanently wedges `gnome-keyring-daemon`'s prompt path.
2. `gnome-keyring-daemon` ties unlock state to a single D-Bus bus and `$XDG_RUNTIME_DIR/keyring/control`, whereas GnuPG hardcodes `/run/user/<uid>/gnupg/S.gpg-agent` across all buses and runtime dirs.
3. With `allow-external-cache` enabled (GnuPG default), `pinentry-qt` calls `libsecret` synchronously during `GETPIN`, causing `git commit` to hang forever whenever `org.freedesktop.secrets` is locked/wedged.

## Key Files

- `modules/nixos/shared/system/default.nix` — `programs.gnupg.agent` (`/etc/gnupg/gpg-agent.conf`), `gpg-pam-unlock` (`pam_exec` rules on `greetd` & `swaylock`), `gpg-unlock` CLI, `pkgs.scrypt`.
- `packages/pass-secret-service/default.nix` & `sync-disk.patch` — patches `pass_secret_service` to re-sync collections, items, and `.properties` from `~/.password-store/secret_service` on `SearchItems` and `CreateItem` so both D-Bus instances see newly added/updated/deleted secrets.
- `packages/pinentry-tmux/pinentry.sh` & `test.sh` — display adoption, active-tmux-client popup routing for TUI panes and empty-`GPG_TTY` requests, and `/run/user/<uid>/remote/wayland-1` fallback.
- `modules/home-manager/desktops/wayland/niri/default.nix` — `services.gnome-keyring.enable = mkForce false` (overrides `niri-flake`'s default so Home Manager's `pass-secret-service` assertion passes).
- `users/minttea/home.nix` — enables `services.pass-secret-service` (patched package, default `storePath`) and installs `pkgs.pass`.
- `hosts/desktop/configuration.nix` & `hosts/flowX13/configuration.nix` — conditional `sops.secrets."gpg/passphrase.scrypt"` (`format = "binary"`, `owner = "minttea"`, `mode = "0400"`).
- `.sops.yaml` — `secrets/gpg/.*` rule (desktop, flowX13, portable user age key).

## `age` & `sops-nix` Setup

### Keys & Locations
All host-level decryption uses `age` keys configured in `.sops.yaml` and `hosts/{desktop,flowX13}/configuration.nix`:

| Key | Public key | Private key path |
|---|---|---|
| `desktop` host | `age1r2ev7w50syd2adu9e0uus4dllfqy9yc0j3w6ezdntjcsqn9gqejs34qxh9` | `/var/lib/sops-nix/keys.txt` |
| `flowX13` host | `age1qceaa6au6jdtzeadyax8gq36tt8krt2age4k97sa298qnae4x4lqzlx3ag` | `/var/lib/sops-nix/keys.txt` |
| Portable user | `age1avxj2pmr8s2e4y7ucse6ks5xfwdftu357lec9ty8qvemw68p6epqq3k04y` | `~/.config/sops/age/keys.txt` (or `.age` backup) |

Both `desktop` and `flowX13` set `sops.age.keyFile = "/var/lib/sops-nix/keys.txt"` and export `SOPS_AGE_KEY_FILE` so NixOS `sops-nix` decrypts secrets at boot/activation onto in-memory `ramfs` at `/run/secrets/<name>`.

### `.sops.yaml` Creation Rules & File Patterns
- **Standard YAML secrets** (`secrets/<service>/secrets.yaml` with `secrets.yaml.example` sibling): `openclaw` (desktop only), `github-runner` & `safemolt` (desktop + user), `syncthing` & `dolt` (desktop + flowX13 + user), fallback `secrets/.*\.yaml$` (desktop + flowX13). Referenced in Nix via `sopsFile` + `key`, with `owner`/`mode` (`root` `0400` for host-only secrets like `github-runner/app-key`, `minttea` for user-readable secrets).
- **Binary secrets** (`secrets/gpg/.*` → desktop + flowX13 + user): declared with `format = "binary"` in Nix so `sops-nix` decrypts the SOPS-wrapped JSON blob straight to raw binary bytes at `/run/secrets/gpg/passphrase.scrypt`.
- **Editing / adding secrets:**
  - `sops secrets/<service>/secrets.yaml` edits YAML secrets in place.
  - Binary files must be encrypted with `sops -e -i --input-type binary --output-type binary <path>` (or `--filename-override <path>` so `.sops.yaml` `path_regex` matches).
  - Always `git add` new files under `secrets/` before `./switch.sh` (flakes ignore untracked files), and never leave a 0-byte file (causes `sops-install-secrets: unexpected end of JSON input`).
  - See also `docs/lessons-learned-sops-secrets-injection.md` and `docs/user-feedback-sops.md`.

## Invariants & Pitfalls

| Rule / Pitfall | Why it matters |
|---|---|
| **Never create `~/.gnupg/gpg-agent.conf`** | A user `gpg-agent.conf` completely shadows `/etc/gnupg/gpg-agent.conf`, dropping `pinentry-program`, `no-allow-external-cache`, and `allow-preset-passphrase`. Always configure `programs.gnupg.agent.settings` in NixOS. |
| **Always keep `no-allow-external-cache`** | Without it, `pinentry` calls `org.freedesktop.secrets` → `pass-secret-service` → `gpg` → `gpg-agent` → deadlocks on the pinentry lock. |
| **Never override `services.pass-secret-service.storePath`** | Home Manager passes `--path` to the systemd unit, but the D-Bus `.service` file (used by `remote-session-compositor`'s private `dbus-daemon`) hardcodes `Exec=.../bin/pass_secret_service` without `--path`. Keep the default `~/.password-store`. |
| **Keep `services.gnome-keyring.enable = mkForce false`** | `niri-flake` enables Home Manager's `gnome-keyring` by default, which fails `services.pass-secret-service`'s mutual-exclusion assertion. |
| **`pam_exec` runs as `root` in `greetd` and `minttea` in `swaylock`** | Override `rules.auth.unix.control` to `[success=ok new_authtok_reqd=ok ignore=ignore default=die]` (NixOS defaults to `sufficient`, which short-circuits before `unix.order + 100`), keep `gpg-pam-unlock.control = "optional"` (so `pam_exec`'s `PAM_IGNORE` during `greetd`'s `pam_setcred()` doesn't abort greeter startup), and terminate with `pam_permit.so` (`sufficient`) at `unix.order + 200` before `pam_deny.so`. Guard `[ "${PAM_USER:-}" = "minttea" ] || exit 0` (skips `greeter`), drop to `minttea` via `runuser` when UID 0, read stdin with `IFS= read -r -d ""` (Linux-PAM appends a NUL byte `\0`), background the unlock, and invoke `${pkgs.gnupg}/libexec/gpg-preset-passphrase` (in `libexec/`, not `bin/`). Never pass passwords in `argv` or `environ`. |
| **Use `format = "binary"` for `passphrase.scrypt`** | `scrypt enc` outputs raw binary and `scrypt dec -P <file>` reads the passphrase from stdin (`-P`), so `sops-nix` places the raw ciphertext directly on in-memory `ramfs` at `/run/secrets/gpg/passphrase.scrypt` with no temp file. |
| **Pass explicit `scrypt` params (`--logN 15 -r 8 -p 1`)** | Avoids `scrypt enc`'s default 5-second CPU time (`-t 5`) and host-RAM scaling across desktop (61 GB) and flowX13 (16 GB). |
| **Flatpak Secret portal** | `pass-secret-service` implements `org.freedesktop.secrets`, not `org.freedesktop.impl.portal.Secret`. Native Nix apps work directly; sandboxed Flatpaks requesting the XDG Secret portal will not. |
| **SSH public-key login does not auto-unlock** | SSH key auth never sends your Linux login password to PAM. If `gpg-agent` is already unlocked (within the 24h TTL), SSH works with no prompt; after a headless reboot, run `gpg-unlock` once or let `pinentry-tmux` prompt. |
| **Stopping legacy `gnome-keyring-daemon`** | Use `pkill -f gnome-keyring-daemon` (the binary name exceeds Linux's 15-char `comm` limit, so plain `pkill gnome-keyring-daemon` matches nothing and leaves `pass-secret-service.service` stuck in `activating (start)` waiting for `org.freedesktop.secrets`). |

## PAM Auth Stack Advisory (`greetd` & `swaylock`)

The generated `auth` stack on `greetd` and `swaylock` is:

```text
1. auth [success=ok new_authtok_reqd=ok ignore=ignore default=die] pam_unix.so
2. auth optional                                                   pam_exec.so gpg-pam-unlock
3. auth sufficient                                                 pam_permit.so
4. auth required                                                   pam_deny.so
```

- **Why `pam_permit.so` is safe here:** `pam_unix.so` uses `default=die`, so any auth failure aborts at line 1 before `pam_exec` or `pam_permit` can run. `pam_permit.so` only exists so `greetd`'s `pam_setcred()` returns `PAM_SUCCESS` (since `pam_exec.so` returns `PAM_IGNORE` for `setcred`).
- **No lockout risk:** `gpg-pam-unlock` is `optional` and backgrounds itself; missing/mismatched `passphrase.scrypt` or a dead `gpg-agent` cannot block login/unlock. `/etc/pam.d/login` (TTY), `sudo`, and `sshd` are untouched.
- **Warning when adding other PAM auth factors:** Because `rules.auth.unix.control` is `lib.mkForce`d on `greetd` and `swaylock`, **revisit these rules before enabling `fprintd`, `pam_u2f`, or any other PAM auth module** so they don't get bypassed or short-circuited by `pam_unix` (`default=die`) or `pam_permit`.

## Rotating the Linux Login Password or GPG Passphrase

If either password changes, re-encrypt `secrets/gpg/passphrase.scrypt` (interactive `zsh`, never commit plaintext):

```zsh
cd /home/minttea/dotfiles
mkdir -p secrets/gpg
nix shell nixpkgs#scrypt nixpkgs#sops
```

Inside that shell (enter your **GPG passphrase** first, then your **Linux login password** twice when `scrypt` prompts):

```zsh
read -rs "gpg_pw?1/2 GPG passphrase: "; echo
f=secrets/gpg/passphrase.scrypt
printf "%s\n" "$gpg_pw" | scrypt enc --logN 15 -r 8 -p 1 - "$f"
unset gpg_pw
sops -e -i --input-type binary --output-type binary "$f"
exit
```

Then `git add secrets/gpg/passphrase.scrypt` and `./switch.sh nixos`.

## Verification

```zsh
# Unit + real-tmux integration tests for pinentry-tmux
bash packages/pinentry-tmux/test.sh

# Build patched pass-secret-service (runs upstream pytest suite)
nix build --no-link --impure --expr '(builtins.getFlake (toString ./.)).homeConfigurations."minttea@desktop".config.services.pass-secret-service.package'

# Flake evaluation check
nix flake check --no-build

# Live checks after switching
gpg-unlock
busctl --user list | grep secrets
gpg --clearsign <<< test >/dev/null
```
