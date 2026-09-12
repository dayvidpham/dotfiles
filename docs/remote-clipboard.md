# Remote clipboard (laptop <-> desktop)

Bidirectional clipboard for headless `ssh` sessions, with no waypipe and no
graphical session required on the desktop.

## Pieces

| Host | Artifact | Role |
|------|----------|------|
| flowX13 (laptop) | `CUSTOM.services.clipd` (home-manager) | `clipd`, a small HTTP-over-unix-socket daemon that reads/writes the laptop's `wl-clipboard`; runs as a *user* service so it inherits `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` from niri |
| flowX13 | `~/.ssh/config` (`Host desktop`) | `RemoteForward /run/user/1000/clipd.sock /run/user/1000/clipd.sock` |
| desktop | `CUSTOM.clipboardTunnel` | headless sway clipboard compositor + `clip-sync`, which mirrors the peer clipboard into it |
| both | `clip` CLI | talk to the peer daemon |

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

- **laptop -> desktop**: `clip get` (or `clip-sync`) reads the peer's
  `wl-clipboard` over the forwarded socket.
- **desktop -> laptop**: `clip put` writes into the peer's `wl-clipboard`.
- The desktop's `clip-sync` service polls the peer every second and mirrors
  changes into the headless compositor's clipboard, so GUI apps living in that
  compositor can paste without any manual step.

## Caveats

- **Two clipboards.** The headless compositor owns its own selection, separate
  from the interactive session (niri on `wayland-1`). `clip-sync` populates the
  *headless* clipboard; it does not reach into niri's. Processes that talk to
  the peer directly (`clip get`, or the terminal) are unaffected.
- **Socket path.** `clipd` listens at `$XDG_RUNTIME_DIR/clipd.sock`
  (`/run/user/1000/clipd.sock` for the standard first user), specified as
  `%t/clipd.sock` in the unit so systemd expands it. The ssh `RemoteForward`
  destination must match. Override `socketPath` if needed.
- **`clipd` is a user service.** It runs only while a graphical session exists
  (bound to `graphical-session.target`, gated on `WAYLAND_DISPLAY`). No
  session means no clipboard to serve: `wl-paste` yields nothing (`/clip` is
  204) and the peer sees a missing socket.
- **Deprecated `--control`/`recon`.** not used here; a dropped `ssh` tears the
  forward down until the next connection.
