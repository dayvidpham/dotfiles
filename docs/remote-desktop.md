# Persistent remote session (headless sway + wayvnc)

A long-lived sway session on the desktop whose windows survive viewer
disconnects. Complementary to waypipe: waypipe forwards individual apps with no
persistence; this is a whole-session model you attach to and detach from.

## Pieces (desktop)

| Unit | Runs | Role |
|------|------|------|
| `remote-session-compositor` | headless sway, own `XDG_RUNTIME_DIR=/run/user/1000/remote` | the session; runs the user's sway config minus session-management execs, plus `waybar` |
| `remote-session-vnc` | `wayvnc` | exports the session over VNC |

Both are system services running as the user; the compositor keeps running
regardless of whether a viewer is attached.

## Exposure: tailnet only

wayvnc **never binds 0.0.0.0**. With `tailnetOnly = true` (default) the wrapper
resolves this node's Tailscale IPv4 from `tailscale0` at start and binds only
that, so the listener does not exist on any other interface. If the interface
has no address (Tailscale down) the service refuses to start rather than fall
back. `networking.firewall.trustedInterfaces = [ "tailscale0" ]` (from the
tailscale module) leaves it reachable on the tailnet.

The address is read from the interface (`ip -4 addr show dev tailscale0`) rather
than `tailscale ip`, which would need root/operator privileges.

## Connecting (from flowX13)

No tunnel needed — connect directly over the tailnet:

```sh
vncviewer desktop:5900          # or 100.64.0.3:5900
```

Any RFB client works (TigerVNC `vncviewer`, `gtk-vnc`/`gvncviewer`, Remmina).
Closing the viewer leaves the session and its windows running.

`tailnetOnly = false` plus `address = "127.0.0.1"` is an escape hatch for the
old ssh-tunnel model (`ssh -L 5900:127.0.0.1:5900 desktop`). Wildcard bind
addresses are rejected by an assertion.

## Clipboard

`wayvnc` 0.10 has **no clipboard support**, so copy/paste over VNC does not
work. Use the ssh clipboard stack instead (`docs/remote-clipboard.md`), which is
independent of the transport.

## Caveats

- VNC authentication/encryption is disabled: the tailnet (WireGuard) provides
  transport encryption and device authentication. To expose beyond the tailnet,
  enable wayvnc auth (TLS cert/key or RSA-AES, `enable_auth`).
- The compositor renders on the **AMD iGPU** (`WLR_RENDERER=gles2`,
  `WLR_RENDER_DRM_DEVICE=/dev/dri/by-path/pci-0000:16:00.0-render`) with
  `WLR_RENDERER_ALLOW_SOFTWARE=1` as a fallback. The AMD/Mesa (`radeonsi`) path
  is used rather than the NVIDIA node for reliability with headless EGL; it
  brings dmabuf support, so clients can use GL/Vulkan and wayvnc can use its
  dmabuf path. Set `renderDevice = null` to fall back to software (pixman).
- One virtual output; resolution is the wlroots headless default.
- The sway config is the user's, filtered to drop the session-management execs
  (same transformation as the waypipe wrapper); keep the two in sync if you
  change how the remote session is configured.
