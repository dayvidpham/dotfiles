# dotfiles

A single Nix flake that describes every one of my machines — a Flow X13 laptop,
a desktop workstation, and a couple of WSL hosts — plus the developer tooling
that runs on them. Everything is declarative: NixOS system config, Home Manager
user config, custom packages, themes, secrets, and the agent workflows I use to
maintain it all.

The flake is the source of truth. There is no imperative setup: flashing a host
means pointing `nixos-rebuild` at this repo and switching.

## Overview

- **Declarative & reproducible.** `flake.nix` pins every input (nixpkgs stable,
  unstable, hardware, Home Manager, and a set of personal flakes) in
  `flake.lock`.
- **Composable modules.** Hosts assemble from a shared base plus opt-in feature
  modules under a single `CUSTOM.*` option namespace, so hosts stay thin and
  behaviour is shared where it can be.
- **Multi-channel by design.** Stable and unstable nixpkgs are both available,
  and packages are selected per-need (e.g. kernel + NVIDIA driver always come
  from the same channel).
- **Secrets encrypted at rest.** [sops-nix](https://github.com/Mic92/sops-nix)
  decrypts secrets at activation with an age key that never enters the store.

## Hosts

Standard hosts are built by `mkHost` in `flake.nix`, which always applies the
shared base modules and then any opt-in features:

| Host | Platform | Notes |
|------|----------|-------|
| `flowX13` | ASUS Flow X13 (AMD iGPU + NVIDIA dGPU) | niri Wayland session, `nvidia-enabled` boot specialization, `powermode` TLP overlay |
| `desktop` | 32-core workstation + RTX 4090 | GitHub Actions runner pool, persistent remote session, Sunshine |
| `wsl` | NixOS-WSL | Sway, GitLab runner, Tailscale |
| `flowX13-wsl` | NixOS-WSL | Same WSL base, laptop-specific user config |

MicroVM guests are defined as minimal standalone configurations (not full
hosts):

| Guest | Purpose |
|-------|---------|
| `llm-sandbox` | Disposable sandbox for running LLM agents |
| `runner-vm-debug` | Started manually to debug the per-job runner microVMs |

`hosts/legacy-desktop/` is a retired configuration kept for reference and is no
longer wired into the flake outputs.

Home Manager configurations are exposed as `minttea@<host>`:
`minttea@flowX13`, `minttea@desktop`, `minttea@wsl`, `minttea@flowX13-wsl`.

## Repository layout

```
flake.nix            # Inputs, host builder, packages, checks, home configs
switch.sh            # Rebuild helper: home-manager (default) or nixos
hosts/               # Per-machine configuration.nix + hardware-configuration.nix
modules/
  nixos/             # System modules: desktops, hardware, services, virtualisation
  home-manager/      # User modules: programs, services, theme, games
packages/            # Custom Nix packages (see below)
programs/neovim/     # Neovim configuration
users/minttea/       # User-level home.nix + per-host overrides
secrets/             # sops-encrypted secrets (never plaintext)
docs/                # Deep-dive design docs (see Documentation)
scripts/             # Operational helpers (VM, tailscale, runners, ...)
agent/               # Agent/tooling configuration and Aura Protocol artifacts
llm/                 # Prompts and research notes
templates/           # Reusable document/prompt templates
```

## Quick start

Rebuild the current machine without invoking system change detection by hand:

```bash
./switch.sh          # home-manager switch --flake .   (default)
./switch.sh nixos    # sudo nixos-rebuild switch --flake .
```

`./switch.sh nixos` drains the GitHub runner pool first when the
`github-runner-drain` helper is on `PATH`; set `SWITCH_NO_DRAIN=1` to skip that
(for example on the first rebuild that introduces the pool module).

The equivalent explicit commands:

```bash
# A specific host
sudo nixos-rebuild switch --flake .#desktop

# A specific Home Manager configuration
home-manager switch --flake .#minttea@desktop
```

### Validating a change

Because evaluation only checks syntax, run both an eval and a build before
committing:

```bash
# Flake check — must pass before commit
nix flake check --no-build 2>&1

# Actual build of a host's system closure (catches runtime/eval errors)
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --no-link

# Cheap syntax-only sanity check on a single option path
nix eval --impure .#nixosConfigurations.<host>.config.<path> --apply 'x: "ok"'
```

There is also a bespoke check, `checks.x86_64-linux.flowX13-gpu-profiles`, that
asserts the Flow X13's base profile and its `nvidia-enabled` specialization
expose the correct drivers, PRIME setup, udev rules, and niri overlay.

## Theming

The desktop theme is **balcony**, vendored under `packages/themes/balcony/` and
wired in through `packages/waybar-balcony`. It is selected per host via
`GLOBALS.theme` in the Home Manager configuration in `flake.nix`.

## Secrets

Secrets are stored encrypted with sops and decrypted at activation by
[sops-nix](https://github.com/Mic92/sops-nix) using an age key at
`/var/lib/sops-nix/keys.txt`. `.sops.yaml` defines the encryption rules; the
encrypted files live under `secrets/`. Nothing decrypted is ever committed or
placed in the Nix store.

Notable secrets include the Syncthing API key, the Dolt federation password,
and the GitHub runner registration token and App private key. See
`docs/lessons-learned-sops-secrets-injection.md` and
`docs/user-feedback-sops.md` for the design and troubleshooting notes.

## Custom packages

Defined in `packages/` and exported through the flake's overlay:

| Package | Description |
|---------|-------------|
| `run-cwd` | Launch a program with the working directory of the invoking shell |
| `scythe` | Lightweight screenshot utility (saves to `~/Pictures/scythe`) |
| `waybar-balcony` | Waybar configuration for the balcony theme |
| `ImPlay` | mpv-based image/video viewer |
| `pinentry-tmux` | `pinentry` that prompts inside tmux |
| `zotero` | Pinned Zotero build with packaging fixes |
| `evbridge` | Patched input bridge used by the Sunshine stream |
| `dwl`, `clip` | Wayland compositor / clipboard helpers |

`packages/rofi-network-manager` is a Git submodule (upstream project, not mine).

## Neovim, tmux, and remote desktop

These three cut across hosts and are each split between a **Nix layer** (packages,
services, and wiring, applied by a rebuild) and a **live-editable config layer**
(symlinked out-of-store, so edits take effect without a rebuild).

### Neovim

Defined by the Home Manager module in `programs/neovim/default.nix`, imported
into every `minttea@*` configuration. It has two halves:

- **Nix side** — enables `programs.neovim`, pins the runtime toolchain (LSPs such
  as `lua-language-server`, `nixd`, `clangd`, `rust-analyzer`, and the Python
  stack, plus `ripgrep`/`fd`), and builds the tree-sitter grammars with
  `nvim-treesitter.withPlugins`. The grammars and parsers are exposed at stable
  paths under `~/.local/share/nvim/nix/` because `lazy.nvim` resets
  `runtimepath` during setup.
- **Lua side** — `programs/neovim/nvim/` is a kickstart.nvim-derived config
  (`init.lua` plus `lua/`), symlinked into `~/.config/nvim/minttea`.

Plugin management is deliberately split: most plugins are fetched by
`lazy.nvim` at runtime, while parsers and language servers are Nix-provided (the
config tells Mason to skip anything Nix already installs). `nixd` is wired to
evaluate **this** flake using `$HOST`/`$USER`, so NixOS and Home Manager option
completion follows whichever host you are on.

### tmux

Split between a Home Manager client half and a NixOS server half:

- **Client** — `modules/home-manager/programs/tmux/` enables `programs.tmux`
  (prefix `M-Space`, vi copy mode; `resurrect`, `continuum`, `logging`, and
  `yank` plugins) and builds helper scripts: `tmux-sessionizer` (fzf + zoxide),
  `tmux-move-window`, `tmux-client-size`, and `tmux-repo-theme` (tints a pane by
  the git repo it sits in). Keybindings live in `keybindings.tmux`, symlinked
  out-of-store for live editing, and Claude Code sessions are captured and
  restored across `resurrect` saves.
- **Server** — `modules/nixos/programs/tmux/` defines
  `CUSTOM.programs.tmux.server`: a systemd system service that runs a tmux
  server as the user with lingering enabled and `KillMode = none`, so it starts
  at boot and survives rebuilds and session closures. `TMUX_TMPDIR` is pinned to
  the login runtime dir so shells inside the remote session attach to the same
  server.

### Remote desktop

A persistent, whole-session model (versus one-off `waypipe` app forwarding): a
headless compositor runs on the desktop and you attach or detach with a VNC
viewer at any time. It is a server module, a client helper, and an optional
audio service.

- **Server** — `modules/nixos/services/remote-session/` defines
  `CUSTOM.services.remote-session`:
  - `remote-session-compositor` runs a headless sway session with its own
    `XDG_RUNTIME_DIR` and a **private D-Bus session bus**, so it cannot steal the
    physical desktop's single-instance apps or its one portal per bus. It renders
    on a DRM render node (`WLR_RENDERER=gles2`, software fallback) and runs the
    user's sway config minus the session-management execs, plus `waybar`.
  - `remote-session-vnc` runs `wayvnc`, bound **tailnet-only** by resolving the
    `tailscale0` IPv4 at start. An assertion rejects wildcard binds and the
    service refuses to start when Tailscale is down, so the listener never
    exists off the tailnet.
  - `clip-peer-sync` (optional) mirrors a peer clipboard into the session through
    the bundled `clip` CLI.
- **Client** — `modules/home-manager/programs/remote-desktop/` defines
  `CUSTOM.programs.remote-desktop`, which provides the `remote-desktop` command:
  it opens an `ssh -R` forward for the clipboard socket (multiplexed with
  `ControlMaster`) for the viewer's lifetime, then launches the VNC viewer. It
  disables the viewer's own clipboard because the ssh stack is the single
  clipboard authority (no last-writer races).
- **Audio** — `modules/home-manager/services/remote-audio/` streams the
  session's PipeWire null sink to the client over RTP (roc) with Reed–Solomon
  FEC, bound to the tailnet interface.

See [`docs/remote-desktop.md`](./docs/remote-desktop.md) and
[`docs/remote-clipboard.md`](./docs/remote-clipboard.md) for the full design,
and `CUSTOM.services.sunshine` for the separate NVENC game-streaming path.

## Development workflow

This repo is maintained with the **Aura Protocol**: work flows through Beads
tasks and a fixed set of agent roles (Architect → Reviewer → Supervisor →
Worker), with all three reviewers required to ACCEPT before a plan is ratified.
See [`AGENTS.md`](./AGENTS.md) for the full protocol, coding constraints, commit
format, and the mandatory session-close checklist.

Conventions worth knowing:

- **Commits** use `git agent-commit -m "..."` (signed, no passphrase prompt),
  in `type(scope): description` form.
- **Beads** (`bd`) tracks work from any worktree; the `.beads` directory is
  redirected to the parent repo so all worktrees share one database.
- **Quality gates** — typecheck/build and `nix flake check --no-build` must pass
  before making a commit.

## CI

`.github/workflows/runner-image.yml` builds, pushes, and keylessly signs (Sigstore)
the self-hosted GitHub runner container image on manual dispatch. The NixOS
runner module pins the resulting digest.

## Documentation

Design notes and runbooks live in [`docs/`](./docs):

- [`remote-desktop.md`](./docs/remote-desktop.md) — persistent headless sway session over wayvnc
- [`remote-clipboard.md`](./docs/remote-clipboard.md) — bidirectional clipboard over the ssh tunnel
- [`github-runner.md`](./docs/github-runner.md) — self-hosted runner module on the desktop
- [`runner-vm-spike.md`](./docs/runner-vm-spike.md) — per-job Cloud Hypervisor runner VMs
- [`beads-dolt-architecture.md`](./docs/beads-dolt-architecture.md) — Beads + Dolt server architecture
- [`debug-vm.md`](./docs/debug-vm.md) — debug VM structure, networking, and security
- [`agent-sandbox.md`](./docs/agent-sandbox.md) — sandboxed agent execution plan

## License

[MIT](./LICENSE) © David Huu Pham
