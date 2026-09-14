# Persistent remote session (headless sway + wayvnc)

A long-lived sway session on the desktop whose windows survive viewer
disconnects. Complementary to waypipe: waypipe forwards individual apps with no
persistence; this is a whole-session model you attach to and detach from.

## Pieces (desktop)

| Unit | Runs | Role |
|------|------|------|
| `remote-session-compositor` | headless sway, own `XDG_RUNTIME_DIR=/run/user/1000/remote` | the session; runs the user's sway config minus session-management execs, plus `waybar` |
| `remote-session-vnc` | `wayvnc` | exports the session over VNC on `localhost:5900` |

Both are system services running as the user; the compositor keeps running
regardless of whether a viewer is attached.

## Connecting (from flowX13)

wayvnc listens on localhost only, so tunnel it over the ssh you already have:

```sh
ssh -L 5900:127.0.0.1:5900 desktop          # then, in another terminal:
vncviewer localhost:5900                     # any RFB client works
```

TigerVNC's `vncviewer`, `gtk-vnc`/`gvncviewer`, or Remmina all work. Closing
the viewer leaves the session (and its windows) running; reconnect later.

To reach it without a tunnel, set `CUSTOM.services.remote-session.address` to a
tailnet address and enable wayvnc auth (`enable_auth`, TLS cert/key, password)
— deliberately not enabled here.

## Clipboard

`wayvnc` 0.10 has **no clipboard support**, so copy/paste over VNC does not
work. Use the ssh clipboard stack instead (`docs/remote-clipboard.md`), which is
independent of the transport.

## Caveats

- The compositor renders with `WLR_RENDERER=pixman` (software); fine for
  terminals/editors, weaker for GPU-heavy apps.
- One virtual output; resolution is the wlroots headless default.
- The sway config is the user's, filtered to drop the session-management execs
  (same transformation as the waypipe wrapper); keep the two in sync if you
  change how the remote session is configured.
- No VNC auth; bind to localhost and tunnel.
