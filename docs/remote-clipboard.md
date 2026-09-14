# Remote clipboard (laptop <-> desktop)

Automatic **bidirectional** clipboard over the ssh tunnel that accompanies the
VNC session. Carries `text/plain` and `image/png`. The VNC viewer's own
clipboard is disabled so this is the single clipboard authority (no races).

## Pieces

| Host | Artifact | Role |
|------|----------|------|
| flowX13 (laptop) | `CUSTOM.services.clipd` (home-manager) | `clipd`: HTTP-over-unix-socket daemon serving the laptop's `wl-clipboard` (`GET` read, `PUT` write); a *user* service, so it inherits `WAYLAND_DISPLAY` |
| flowX13 | `CUSTOM.programs.remote-desktop` | launches the VNC viewer, opens a dedicated `ssh -R` for the clipd socket for the viewer's lifetime, and disables the VNC viewer's own clipboard |
| desktop | `CUSTOM.services.remote-session` (clipboard) | `clip-peer-sync` reconciles the peer clipboard with the remote session's clipboard; provides the `clip` CLI |
| desktop | `CUSTOM.services.clip-sync` (home-manager) | same reconciler for a local login session, if you log in directly |

## Synchronisation

`clip-sync` polls both clipboards (~1s) and reconciles them against a single
"last agreed" hash:

```
if peer != last:   copy peer -> local,  last = peer
elif local != last: PUT local -> peer,  last = local
```

So a value that arrived from the peer is never pushed back (no feedback loop),
and a copy on either machine propagates to the other. Simultaneous changes
resolve last-writer-wins.

## Usage (manual)

```sh
clip info                 # MIME types the peer offers
clip get                  # peer text -> stdout
clip get image/png > shot.png
clip put < notes.txt
clip put image/png < screenshot.png
clip ping
```

## Caveats

- **`clipd` is a user service** bound to `graphical-session.target`. No laptop
  session means nothing to serve; the tunnel socket may be absent.
- **Peer socket** is `/run/user/1000/clipd.sock` on both ends, created on the
  desktop by sshd from the `remote-desktop` helper. Desktop sshd sets
  `StreamLocalBindUnlink=yes` so a stale socket cannot wedge a later forward.
- **VNC clipboard is off** (`AcceptClipboard=0`, `SendClipboard=0` in
  `~/.config/tigervnc/default.tigervnc`); the tunnel replaces it. RFB is
  text-only anyway, so the tunnel is also what carries images.
- Reading the local clipboard each tick means a large image is re-read/hashed
  periodically; fine for occasional screenshots.
