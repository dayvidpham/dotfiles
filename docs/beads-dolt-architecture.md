# Beads + Dolt Server Architecture

## Overview

Beads is an issue tracker for AI-supervised coding workflows. It uses Dolt
("Git for databases") as its storage backend, accessed via a shared
MySQL-compatible SQL server managed by systemd.

```
                        User Shell
                            |
                    bd <command>
                            |
              +-------------+-------------+
              |                           |
         Read/Write                  Federation
      (MySQL protocol)            (push / pull)
              |                           |
              v                           v
  +------------------------+   DOLT_REMOTE_USER
  |   dolt sql-server      |   DOLT_REMOTE_PASSWORD
  |   (systemd user svc)   |         |
  |                        |         v
  |   127.0.0.1:3307       |   DOLT_PUSH / DOLT_PULL
  |   --no-auto-commit     |   (Hosted Dolt / S3 / GCS)
  +------------------------+
              |
              v
  +------------------------+
  |  ~/.beads/dolt/        |
  |  +-- beads/            |  dotfiles tracker
  |  +-- beads_aura/       |  aura framework
  |  +-- beads_aura-plugins|  aura-plugins
  |  +-- beads_unified-..  |  schema dev
  +------------------------+
```

## Home-Manager Module Hierarchy

Enabling `CUSTOM.programs.beads` cascades into the dolt-server service:

```
home.nix / home.desktop.nix
  |
  |  CUSTOM.programs.beads.enable = true
  |
  v
+---------------------------------------+
| programs/beads/default.nix            |
|                                       |
|  - home.packages = [ pkgs.beads ]     |
|  - CUSTOM.services.dolt-server = true |  <-- hard dependency
|  - federation.* (opt-in)              |
|  - federation.secrets.* (sops-nix)    |
+---------------------------------------+
  |
  v
+---------------------------------------+
| services/dolt-server/default.nix      |
|                                       |
|  - systemd.user.services.dolt-server  |
|  - home.packages = [ pkgs.dolt ]      |
|  - dataDir, host, port, user          |
|  - noAutoCommit = true (required)     |
+---------------------------------------+
```

### Module Options

```
CUSTOM.programs.beads
 +-- enable                          bool (default: false)
 +-- federation
      +-- remoteUser                 ?str  -> DOLT_REMOTE_USER env var
      +-- remotePasswordFile         ?path -> manual fallback
      +-- secrets
           +-- enable                bool  -> use sops-nix
           +-- sopsFile              path  -> encrypted secrets file
           +-- remotePasswordKey     str   -> key in sops file
                                             (default: "dolt_remote_password")

CUSTOM.services.dolt-server
 +-- enable                          bool (auto-set by beads module)
 +-- package                         pkg  (default: pkgs.dolt)
 +-- dataDir                         str  (default: ~/.beads/dolt)
 +-- host                            str  (default: 127.0.0.1)
 +-- port                            port (default: 3307)
 +-- user                            str  (default: root)
 +-- noAutoCommit                    bool (default: true)
```

## Package Wrapping (flake.nix overlay)

The beads flake input (`~/codebases/beads`) is built with `buildGoModule` and
then wrapped so the `bd` binary has `dolt` on its PATH:

```
flake.nix overlay
 |
 +-- beads.packages.${system}.default   (upstream Go build)
 |
 +-- pkgs.beads = runCommand "beads-wrapped"
      |
      +-- cp -r ${base}/* $out/          (copy upstream package)
      +-- wrapProgram bd --prefix PATH : ${makeBinPath [ dolt ]}
      +-- ln -sf bd beads                (alias)
```

## Transaction Semantics

`--no-auto-commit` is required. Dolt COMMIT (version control) and MySQL COMMIT
(transaction durability) are separate operations. The beads Go code manages both:

```
bd create "new issue"
  |
  |  1. BEGIN              (MySQL transaction)
  |  2. INSERT INTO issues (application write)
  |  3. COMMIT             (transaction durable in working set)
  |
  |  4. CALL DOLT_COMMIT('-Am', message, '--author', actor)
  |     ^-- stages all changes AND creates version snapshot
  |
  done
```

Note: `DOLT_COMMIT('-Am', ...)` is a single Dolt SQL procedure that both
stages all working-set changes and creates a version control snapshot.
The `-A` flag stages all tables; `-m` provides the commit message. This
is separate from the MySQL `COMMIT` which only ensures transaction durability.

If `--no-auto-commit` were off, every MySQL statement would auto-commit,
creating spurious Dolt snapshots and breaking batch semantics.

## Federation (Dolt Remote Push/Pull)

Federation has two config layers:

```
Per-repo (.beads/config.yaml)            Per-user (home-manager)
+------------------------------------+   +---------------------------+
| federation:                        |   | DOLT_REMOTE_USER          |
|   remote: dolthub://org/beads      |   | DOLT_REMOTE_PASSWORD      |
|   sovereignty: T1                  |   |   (from sops-nix or file) |
+------------------------------------+   +---------------------------+
              |                                      |
              +----------------+---------------------+
                               |
                               v
                    CALL DOLT_PUSH(remote, branch)
                    CALL DOLT_PULL(remote, branch)
```

- Remote URL: per-repo, set via `bd dolt set federation.remote <url>`
- Credentials: per-user, set via home-manager module's `federation.secrets`

## Secrets Flow (sops-nix)

```
secrets.yaml (encrypted, git-tracked)
  |
  |  sops-nix decrypt at activation
  v
/run/user/1000/secrets/beads/remote-password
  |
  |  programs.zsh.initExtra
  v
export DOLT_REMOTE_PASSWORD="$(< /run/...)"
  |
  |  available to bd commands
  v
bd dolt push / bd dolt pull
```

The password never enters the Nix store. It exists only in the ephemeral
runtime directory, loaded into the shell environment at login.

Prerequisite: `sops-nix` must be passed via `extraSpecialArgs` in flake.nix
(already done — see line 275). The beads module asserts this at eval time.

## Data Directory Layout

Each subdirectory under `dataDir` is a separate Dolt database, automatically
exposed by the SQL server:

```
~/.beads/dolt/               (server WorkingDirectory)
+-- beads/                   dotfiles issue tracker
|   +-- .dolt/               version control metadata
|   +-- .doltcfg/            database-level config
+-- beads_aura/              aura framework issues
+-- beads_aura-plugins/      aura-plugins issues (117 issues)
+-- beads_unified-schema/    unified schema dev (265 issues)
+-- config.yaml              server-level config
+-- .doltcfg/                global server config
```

New repos running `bd init` with `dolt_mode: server` in their
`.beads/metadata.json` will create their database here automatically.

## systemd Service

```ini
[Unit]
Description=Dolt SQL Server for beads
After=default.target

[Service]
Type=simple
WorkingDirectory=~/.beads/dolt
ExecStartPre=mkdir -p ~/.beads/dolt
ExecStart=dolt sql-server --host 127.0.0.1 --port 3307 --user root --no-auto-commit
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

The beads Go code includes exponential backoff (30s max) for transient
connection errors, handling brief server restarts transparently.

## Known Issues

- **getStore() nil**: `bd dolt commit/push/pull` fail on upstream beads because
  `"dolt"` parent command skips store init. Fix on branch
  `fix/dolt-subcommand-store-init` in `~/codebases/beads/` (pending upstream PR).
- **Shared server accident**: All databases currently live at
  `~/dotfiles/.beads/dolt/` because the server was first started from dotfiles.
  Migration to `~/.beads/dolt/` is tracked but deferred.
- **JSONL backup**: `dolt/` is gitignored (binary). JSONL exports are the only
  git-tracked backup mechanism. Run periodic `bd export --jsonl` or use the
  `scripts/import_jsonl_to_dolt.py` for recovery.
