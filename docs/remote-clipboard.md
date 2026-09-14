# Remote clipboard (laptop <-> desktop)

Bidirectional clipboard over the ssh tunnel that accompanies the VNC session,
carrying `text/plain` **and** `image/png`. VNC's own clipboard channel is
text-only, so this is what makes pasting a laptop **screenshot** into the
remote session work.

## Pieces

| Host | Artifact | Role |
|------|----------|------|
| flowX13 (laptop) | `CUSTOM.services.clipd` (home-manager) | `clipd`: a small HTTP-over-unix-socket daemon serving the laptop's `wl-clipboard`; a *user* service, so it inherits `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` from the session |
| flowX13 | `CUSTOM.programs.remote-desktop` | launches the VNC viewer **and** starts/stops a dedicated `ssh -R` for the clipd socket, so the tunnel's lifetime is the viewer session |
| desktop | `CUSTOM.services.remote-session` (clipboard) | the persistent sway/wayvnc session's clipboard peer-sync (`clip-peer-sync`) mirrors the laptop clipboard into that session, plus the `clip` CLI |
| desktop | `CUSTOM.services.clip-sync` (home-manager) | optional: mirrors the laptop clipboard into a *local* login session (if you log in directly) |

## Usage

On the desktop (or anywhere the forwarded socket exists):

```sh
clip info                 # MIME types the peer offers
clip get                  # peer text -> stdout
clip get image/png > shot.png
clip put < notes.txt
clip put image/png < screenshot.png
clip ping
```

## Flow

- **laptop -> desktop**: `clip get` (or `clip-sync`) reads the laptop's
  `wl-clipboard` over the forwarded socket; `clip-peer-sync` mirrors it into the
  remote session's clipboard so VNC-session apps can paste.
- **desktop -> laptop**: `clip put` writes into the laptop's `wl-clipboard`.
- **Tunnel lifecycle**: `remote-desktop` runs
  `ssh -N -o ControlMaster=no -o ControlPath=none -o ExitOnForwardFailure=yes -R …`
  before the viewer and kills it on exit. A dedicated connection is required
  because a reused `ControlMaster` does not add `-R`; auth is key-based, so no
  password prompt.

## Caveats

- **wayvnc clipboard is text-only.** For images, use `clip`/`clip-sync`.
- **`clipd` is a user service**: no laptop session means nothing to serve
  (`/clip` returns 204).
- **Peer socket** is `/run/user/1000/clipd.sock` on both ends. The desktop side
  is created by sshd from the `remote-desktop` helper; desktop sshd sets
  `StreamLocalBindUnlink=yes` so a stale socket from an unclean disconnect does
  not block a later forward.
- **Display name**: the remote session runs in a dedicated
  `XDG_RUNTIME_DIR` (`/run/user/1000/remote`) with a stale-socket pre-clean, so
  its compositor socket is deterministically `wayland-1` (sway 1.12 has no
  `--socket` flag). `clip-peer-sync` uses the `remote-session` options, not a
  duplicate literal.
