# Remote clipboard (laptop ↔ desktop)

Given a graphical laptop session, when text or PNG is copied on either machine,
then one independent SSH tunnel should reconcile it with the shared remote Sway
clipboard. It should not depend on a VNC or Moonlight viewer being open.

This documents repository changes, **not an applied migration**. Existing desktop
services were reported active; no live commands or activation were performed.

## Owners and lifecycle

| Host | Component | Role |
|---|---|---|
| flowX13 | `CUSTOM.services.clipd` | Graphical-session user daemon serving text/PNG over a Unix HTTP socket; inherits the local Wayland environment |
| flowX13 | `CUSTOM.services.clip-tunnel` | Singleton `clip-tunnel.service`; foreground SSH remote Unix-socket forward, independent of viewers |
| desktop | `clip-peer-sync` / remote-session clipboard | **One** headless reconciler for the Sway used by both wayvnc and Sunshine |
| desktop | `CUSTOM.services.clip-sync` | Existing physical niri clipboard reconciler; separate local Wayland display |

`clipd` and `clip-tunnel` belong to `graphical-session.target`; the tunnel wants
and starts after `clipd` and stops with that session. A clipd restart should not
strand the tunnel through a `Requires=` stop dependency. The local socket defaults to clipd's socket
(`%t/clipd.sock`, expanded by systemd), and the desktop forward defaults to
`/run/user/1000/clipd.sock`. Adapt the remote path to the actual remote UID.
The desktop sshd uses `StreamLocalBindUnlink=yes` to recover a stale remote socket
on the next forward; do not manually unlink sockets while an owner may be live.

**Sharing continues with no viewer and even while viewing another host.** The
VNC helper only attaches to a viewer and warns when its host differs from the
configured clipboard host; it never retargets or owns this service. To opt out,
disable `CUSTOM.services.clip-tunnel.enable` and apply the reviewed configuration.
To retarget, explicitly change its host and configure the destination reconciler.
Do not treat closing a viewer as revoking clipboard sharing.

## SSH prerequisites and recovery

Before activation, provision the destination's **verified** known-host entry and
a usable noninteractive key/agent in the user service environment. Do not bypass
host-key verification to silence a failure. A key needing an unavailable prompt
will not authenticate: arrange/unlock the agent and ensure the user manager sees
its socket, or use another approved noninteractive credential arrangement.

The transport explicitly disables multiplexing (`-S none`, `ControlMaster=no`,
`ControlPersist=no`) and backgrounding (`ForkAfterAuthentication=no`). It uses
`BatchMode=yes`, `StrictHostKeyChecking=yes`, `ExitOnForwardFailure=yes`,
`ConnectTimeout=10`, `ConnectionAttempts=1`, `ServerAliveInterval=30`, and
`ServerAliveCountMax=3`. systemd retries failures every 5 seconds; the unit declares
`TimeoutStartSec=15` and `TimeoutStopSec=10`. Because it is `Type=simple`, systemd
considers it started immediately: the startup setting is **not** a total SSH
authentication deadline or proof that the forward is ready. `ConnectTimeout`
bounds connection setup; keepalives detect an unresponsive established peer.
An active unit alone does not establish clipboard readiness. Missing trust,
unavailable credentials or a forward collision should be visible in
`journalctl --user -u clip-tunnel`; repair the prerequisite and let the singleton
retry. It must not open passphrase dialogs or reuse an unrelated interactive SSH
master.

## Synchronisation and usage

The existing reconciler polls each side (~1s) against the last agreed payload
hash. A peer change is copied locally; otherwise a local change is sent to the
peer. An incoming payload is not immediately echoed back. Simultaneous changes
are resolved by that polling order, not a distributed transaction. Large PNGs
are re-read/hashed periodically.

```sh
clip info
clip get
clip get image/png > shot.png
clip put < notes.txt
clip put image/png < screenshot.png
clip ping
```

The tunnel/reconciler is the sole clipboard authority. Keep TigerVNC
`AcceptClipboard=0`, `SendClipboard=0`, `SetPrimary=0`, `SendPrimary=0`; do not add
another clipboard channel for Sunshine. See the [desktop guide](<remote-desktop.md>)
for shared-window, dictation, input and audio acceptance tests.

## Migration BEFORE activation

1. Save work and close all old viewers. **The old Sunshine compositor's windows
   cannot migrate and will close on the switch**; obtain approval before activation.
2. The old viewer helper used a persistent SSH master at `~/.ssh/clip-%h` and
   closing viewers may not stop it. Inspect the effective **old** path without
   connecting:

   ```sh
   ssh -G -o 'ControlPath=~/.ssh/clip-%h' desktop
   ```

   Read its `hostname` and `controlpath` entries. `%h` means the final remote
   `HostName`, **not** the command-line alias (`%n`). For example, if `hostname`
   is `50.92.252.186`, the old socket is `$HOME/.ssh/clip-50.92.252.186`, not
   `$HOME/.ssh/clip-desktop`. Verify the actual output and original config; do not
   assume this example remains current or target the normal `socket.*` master.
3. Once viewers are closed and the exact old control path is verified, the human
   operator can ask that master to exit:

   ```sh
   ssh -S "$HOME/.ssh/clip-50.92.252.186" -O exit desktop
   ```

   Substitute **only the verified path** if different. This command targets the
   legacy clipboard master, not all SSH sessions. If no master exists, inspect
   the error and socket/listener ownership; **do not blindly `rm` a socket**.
   If SSH `HostName` changed since the old master started, current `ssh -G` alone
   cannot locate it: inspect the original configuration and live process before
   selecting a path. Server-side stale forward sockets are recovered by sshd's
   `StreamLocalBindUnlink=yes` on reconnect.
4. Confirm trust/agent prerequisites, review server/client changes, and only then
   perform approved activation. Inspect one user tunnel and one headless
   reconciler; test text, PNG, dictation, viewer independence and reconnect.

These are instructions for an approved future migration; no master was stopped
and no socket was deleted by this work.

## Non-live checks

```sh
nix eval .#checks.x86_64-linux.clipboard-tunnel.drvPath
nix build --no-link .#checks.x86_64-linux.clipboard-tunnel
nix flake check --no-build
```

The mock transport check cannot establish real SSH authentication, Wayland
clipboard interoperability or hardware dictation behavior. Record hardware UAT
separately, including recovery after a network interruption and absence of
forward-bind races with multiple viewers. The selected audio policy is native
Moonlight by default, with explicit mutually exclusive VNC/ROC selection; switching
to VNC audio deliberately closes managed Moonlight, not the remote desktop or
clipboard tunnel. No automatic restore-on-exit. Activation and hardware UAT remain
user-deferred; clipboard results do not imply audio validation.
