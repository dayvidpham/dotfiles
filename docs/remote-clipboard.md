# Remote clipboard (laptop <-> desktop)

Bidirectional clipboard for headless `ssh` sessions, with no waypipe required.

## Pieces

| Host | Artifact | Role |
|------|----------|------|
| flowX13 (laptop) | `CUSTOM.services.clipd` (home-manager) | `clipd`, a small HTTP-over-unix-socket daemon serving the session clipboard via `wl-clipboard`; a *user* service, so it inherits `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` from the session |
| flowX13 | `~/.ssh/config` (`Host desktop`) | `RemoteForward` of the clipd socket to the desktop |
| desktop | `CUSTOM.services.clip-sync` (home-manager) | mirrors the peer clipboard into the **live session's** clipboard (so GUI apps in niri/sway can paste) |
| desktop | `CUSTOM.clipboardTunnel` | headless sway clipboard compositor + a *system* `clip-sync` that mirrors the peer clipboard into it (for GUI apps living there) |
| both | `clip` CLI | talk to the peer daemon directly |

Content scope: `text/plain` and `image/png` (screenshots). Anything else is
rejected with HTTP 415.

## Usage

On the desktop (or anywhere with the forwarded socket):

```sh
clip info                 # what MIME types does the peer offer?
clip get                  # peer text -> stdout
clip get image/png > shot.png
clip put < notes.txt
clip put image/png < screenshot.png
clip ping                 # is the peer daemon reachable?
```

Override the socket with `--socket PATH` or `$CLIP_SOCKET`.

## How it flows

- **laptop -> desktop**: `clip get` reads the peer's `wl-clipboard`; both
  `clip-sync` services poll the peer and mirror changes into their local
  clipboard (session and headless compositor respectively).
- **desktop -> laptop**: `clip put` writes into the peer's `wl-clipboard`.
- **Waypipe is separate**: a waypipe sway session proxies the clipboard with the
  laptop natively (`wl_data_device`); `clipd`/`clip-sync` are for plain ssh.

## The RemoteForward, and trust

`ssh -R` opens a socket on the *remote* (desktop) that tunnels back over the
authenticated ssh connection to the *local* (laptop) clipd:

```
desktop:$XDG_RUNTIME_DIR/clipd.sock  ──ssh──▶  laptop:$XDG_RUNTIME_DIR/clipd.sock
```

- It exposes the **laptop's** clipboard to the desktop while connected, not the
  reverse.
- The socket is unix-only, in the user's runtime dir, owned by the user, mode
  0600: only processes running as that user on the desktop can connect.
- It lives in the user's `~/.ssh/config` (not system-wide), so other local
  users (including root) do not get it.
- Stale-socket hazard: with `StreamLocalBindUnlink=no` (upstream default) a
  socket left by an unclean disconnect blocks the forward. The openssh module
  sets `StreamLocalBindUnlink = "yes"`.
- `ControlMaster`: a forward is only installed by the connection that creates
  the master; a reused master does not add new forwards.

## Caveats

- **Two clipboards on the desktop.** The live session (niri, `wayland-1`) and
  the headless compositor (`/run/user/1000/clip`) are separate selections; each
  gets its own `clip-sync`.
- **`clipd` is a user service**, bound to `graphical-session.target` and gated on
  `WAYLAND_DISPLAY`. No session means no clipboard to serve: `wl-paste` yields
  nothing (`/clip` is 204) and the peer sees a missing socket.
- **Socket path** is `%t/clipd.sock` (systemd expands `%t` to
  `$XDG_RUNTIME_DIR`, normally `/run/user/1000`). The `RemoteForward`
  destination must match.
