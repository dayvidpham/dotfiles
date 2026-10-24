---
name: remote-desktop
description: >-
  Work on the single persistent remote-session headless Sway shared by wayvnc
  and Sunshine/Moonlight: NVIDIA rendering, software VNC capture, NVENC,
  isolated input, shared audio, clipboard lifecycle, resolution and migration.
  Use for remote-session/Sunshine modules, headless Wayland capture, audio/input
  routing, client clipboard tunnels or remote-stream debugging.
---

# Shared remote desktop

## Status and architecture

Repository implementation is **not activation**. Existing desktop services were
reported active before this work; do not stop/restart/activate them without human
approval. User selected **native Moonlight default, manual mutually exclusive
VNC/ROC audio**, and **DO NOT ACTIVATE YET**. Do not report final hardware/audio
acceptance from a configuration or inert synthetic manager check.

Given either viewer reconnects, when attaching to desktop, then it should see the
same windows in **one** `remote-session-compositor`; it should not create its own
compositor or close applications on disconnect.

```text
physical niri ── physical displays/input (unchanged)

remote-session-compositor ── headless Sway, NVIDIA gles2 render node
  runtime /run/user/1000/remote, private D-Bus, shared Firefox profile
  ├─ remote-session-vnc: software capture/encode baseline, tailnet-only
  ├─ sunshine-spike: wlr capture + NVIDIA NVENC
  ├─ sunshine-evbridge: isolated uinput → Wayland virtual input
  └─ clip-peer-sync: ONE headless text/PNG clipboard reconciler

apps → remote_audio → explicit Sunshine capture AND ROC monitor sender
flowX13 clipd ← singleton user clip-tunnel SSH forward ← desktop reconcilers
```

Sunshine derives user/runtime/display from `CUSTOM.services.remote-session`.
It owns **no compositor or sink**. Keep physical niri's existing clipboard sync;
do not add a Sunshine reconciler. Detailed operator guides:
[desktop](<../../../docs/remote-desktop.md>) and
[clipboard](<../../../docs/remote-clipboard.md>).

## GPU and compositor constraints

- Physical niri owns DRM outputs. Use `WLR_BACKENDS=headless` and a shareable
  render node, not a DRM backend that competes for DRM master.
- Shared desktop render node: RTX 4090,
  `/dev/dri/by-path/pci-0000:01:00.0-render`; `WLR_RENDERER=gles2`,
  `WLR_RENDERER_ALLOW_SOFTWARE=1`, `WLR_LIBINPUT_NO_DEVICES=1`.
  `sway --unsupported-gpu` is a compatibility gate, not software rendering.
- Headless dmabuf feedback can log `Failed to get backend DRM FD` because there
  is no KMS scanout device; do not switch to DRM just to remove the message.
- **wayvnc:** software capture/encoding baseline, no `-g` on shared NVIDIA Sway.
  wayvnc/neatvnc hardware encoding uses VA-API; NVIDIA VA-API is decode-only.
  NVIDIA rendering does not imply NVIDIA VNC hardware encoding. Measure real
  capture compatibility and performance; do not claim checks prove it.
- **Sunshine:** keep `capture=wlr`, `output_name=HEADLESS-1`, `encoder=nvenc` and
  the CUDA-enabled unstable package. Default nixpkgs CUDA-off builds lack NVENC.
  Preserve `LD_LIBRARY_PATH=/run/opengl-driver/lib`; no `cap_sys_admin` wrapper
  (secure-exec would discard the loader path and break CUDA/NVENC).
- The one compositor has a private D-Bus and filtered user Sway config: strip
  session-management execs that hijack the physical user manager, preserve
  application/bar configuration and Ghostty's single-instance override. Keep
  `pkgs.dbus` available to the sway wrapper and child processes.
- A separate shared-session Firefox profile avoids the physical session's lock;
  VNC and Moonlight do not need separate profiles because they share one Sway.
- Readiness means a **listening** Wayland socket, not just a pathname. Capture,
  evbridge and clipboard dependents must reconnect after compositor replacement;
  `After=` alone is not crash recovery. A compositor crash can lose windows.

## Input isolation

VNC uses Wayland virtual pointer/keyboard directly. Sunshine creates uinput
`libvirtualhid*` devices which must have `LIBINPUT_IGNORE_DEVICE=1` and be exposed
only through the filtered Sunshine evdev directory. evbridge reads that directory
and emits virtual input into the shared Sway; it must not read physical devices.
Preserve the rescan patch for lazily created devices and the hi-res scroll patch
(whole wheel detents with discrete events, including GTK/Firefox/Ghostty behavior).
`LIBSEAT_BACKEND=noop` does not create an isolated seat: it names seat0.

Retain the installed laptop Moonlight wrapper's
`SDL_MOUSE_RELATIVE_SYSTEM_SCALE=1`; launching unwrapped Moonlight loses trackpad
system scaling. Remote keyboard/pointer events must never appear in physical niri.

## Shared resolution

Only one `HEADLESS-1` exists. Sunshine's `global_prep_cmd` applies Moonlight's
`SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` on **application launch** (`proc.execute`), not
on every connection/resume. VNC sees that same size. **No per-disconnect
reset/undo**: it could resize another still-connected client. The applied mode
persists across disconnect/resume until another launch/manual mode change or
compositor restart (configured baseline `1920x1080@60Hz`). Additional viewers
and resumes do not automatically resize. Do not claim a one-stream cap: pinned
Sunshine source has no supported concurrency-limiting `channels` option.
Overlapping clients share windows, input and size. Use the PID-named Sway IPC
socket under the derived runtime, not the Wayland socket.

## Audio policy — native default, manual VNC/ROC

The sole persistent session sink remains **`remote_audio`**: apps use
`PULSE_SINK=remote_audio`, Sunshine explicitly uses `audio_sink=remote_audio`, and
ROC reads `remote_audio.monitor`. Sunshine owns no additional persistent session
sink, though it may manage temporary internal virtual sinks/default routing as
before. Pinned-source verification showed explicit capture prefers the configured
sink. Do **not** rename the persistent sink to reserved `sink-sunshine-stereo`:
Sunshine's own sink management can duplicate/unload that name. Inspect actual
persistent sink uniqueness. The private Wayland runtime still needs the user's
real PipeWire/Pulse runtime for audio clients.

User chose native Moonlight by default and manually selected VNC/ROC. FlowX13
sets receiver `autostart=false` (generic module default remains true). The installed
`moonlight-qt` and overridden normal desktop entry use fixed
`moonlight-client.scope`, with `Conflicts=remote-audio-recv.service` and
`After=remote-audio-recv.service`; receiver conflicts with that scope without a
reverse ordering edge. The scope preserves caller environment/argv and SDL
scaling; `--expand-environment=no` and `--` preserve literal command arguments.
Duplicate managed launches fail rather than start a second audible client.

`remote-audio-mode native` stops ROC, without launching Moonlight. A managed
Moonlight launch stops ROC before starting. `remote-audio-mode vnc` warns and
**deliberately closes managed Moonlight** before starting ROC; the remote desktop
windows/session and clipboard tunnel remain running. `status` reports actual unit
states, not playback readiness. VNC attachment alone does not select audio.
There is **no restore-on-exit**: selected audio persists until explicit selection
or managed Moonlight launch; a fresh user-manager login defaults to native. ROC
can keep playing with no viewer. Unwrapped `moonlight`, absolute binaries and
`nix run` bypass this policy and must be closed before ROC testing. Direct
receiver starts also close managed Moonlight; use the selector for its warning.
Do not mistake `--audio-on-host` for a local-audio mute flag.

Activation and hardware UAT are explicitly deferred. Do not claim echo-free
behavior or mark audio UAT complete. Test VNC/ROC and native Moonlight for one
audible path, latency and reconnect after approved activation. Same-machine tests
must pin playback to a real sink, not the captured null sink.

## Clipboard service and security

`CUSTOM.services.clip-tunnel` is a singleton graphical-session user service,
wanting/starting after local clipd and forwarding its Unix socket to desktop's
peer socket. Do not add a `Requires=` stop dependency that strands it when clipd
restarts; both services stop with the owning graphical session.
It remains active with no viewer **and while viewing another host**; retarget or
disable it explicitly to change/revoke sharing. `remote-desktop` owns only the
VNC attachment. Keep native VNC/primary clipboard disabled. One headless
reconciler plus existing physical niri sync is sufficient for both viewers.

SSH must explicitly use `-S none`, `ControlMaster=no`, `ControlPersist=no`,
`ForkAfterAuthentication=no`, `BatchMode=yes`, `StrictHostKeyChecking=yes`,
`ExitOnForwardFailure=yes`, bounded connect/keepalive timeouts and systemd retry.
Pre-provision verified known-host trust and a usable unlocked key/agent in the
user service environment. Missing credentials/trust should log and retry, never
prompt or silently bypass verification. Desktop sshd `StreamLocalBindUnlink=yes`
recovers stale remote forward sockets on reconnect.

## Migration BEFORE activation

- Warn the user **before** switching: old `sunshine-compositor` windows cannot
  migrate into the surviving compositor and **will close**. Save work and obtain
  approval; compositor configuration changes can restart other remote apps too.
- Close old viewers. A legacy persistent master may remain at `~/.ssh/clip-%h`.
  Inspect `ssh -G -o 'ControlPath=~/.ssh/clip-%h' desktop` without connecting.
  `%h` is effective `HostName`, not original alias `%n`; verify `controlpath`.
- Human-only retirement, **after verifying the exact old path**:
  `ssh -S "$HOME/.ssh/clip-50.92.252.186" -O exit desktop` if the effective old
  `HostName` is `50.92.252.186`. Substitute the verified path if different.
  This example is not a universal path. Config changes since master startup
  require original config/process inspection. Never blindly delete sockets or
  kill the unrelated normal interactive master.
- Check new SSH prerequisites, review changes and only then activate with human
  approval. Disabling receiver autostart alone does not stop legacy running ROC:
  explicitly select `remote-audio-mode native` after approved client activation,
  and close any unwrapped Moonlight clients before audio testing. Do not execute
  migration/live commands as part of documentation work.

## Verification

Non-live configuration / mocked lifecycle checks:

```sh
nix eval .#checks.x86_64-linux.remote-audio-client.drvPath
nix build --no-link .#checks.x86_64-linux.remote-audio-client
nix eval .#checks.x86_64-linux.shared-remote-session.drvPath
nix eval .#checks.x86_64-linux.clipboard-tunnel.drvPath
nix build --no-link .#checks.x86_64-linux.shared-remote-session
nix build --no-link .#checks.x86_64-linux.clipboard-tunnel
nix flake check --no-build
```

The opt-in `python3 checks/remote-audio-client/inert-lifecycle.py` tests the real
user manager with uniquely named inert units only: simultaneous transitions,
duplicates, parent restart, receiver crash/retry and client failure/exit, with
exclusive sound-lock holders and bounded cleanup. It never targets production
units. These checks do **not** validate real GPU, input, audible audio, clipboard
or network hardware. After approved activation, operator read-only diagnostics include:

```sh
systemctl is-active remote-session-compositor remote-session-vnc sunshine-spike sunshine-evbridge clip-peer-sync
systemctl --user is-active clipd clip-tunnel   # laptop
journalctl --user -u clip-tunnel -b            # laptop
journalctl -u sunshine-spike -b
nvidia-smi
```

Inspect the shared Sway `get_tree`, `get_outputs`, `get_inputs` with its PID-named
IPC socket; inspect sink uniqueness, app sink inputs, Sunshine monitor capture,
ROC source, NVENC logs and encoder engine activity. Debug in order: unit → socket
and output → capture → encoder → isolated input → sink/capture → selected client.

Hardware UAT must include: same terminal/browser windows and app PIDs in both
viewers; detach/reconnect persistence; shared Moonlight resize and overlapping
client disconnect; bidirectional text/PNG clipboard and dictation paste; singleton
tunnel with no viewers/network recovery; approved capture/compositor crash
recovery; physical niri input isolation; wheel/trackpad scaling; and VNC/native
audio under the selected exclusive policy. Do not equate active services with success.

## Pitfalls

| Symptom | Investigate |
|---|---|
| NVENC missing / `Couldn't scale frame: Invalid argument` | CUDA-enabled package and actual encoder logs |
| `Cannot load libcuda.so.1` | Driver loader path and accidental capability wrapper |
| `dbus-daemon` missing | dbus in compositor runtime PATH |
| Capture stays alive but no video after Sway crash | Dependency restart propagation and fresh socket readiness |
| Mouse/scroll missing or host receives it | evbridge rescan/scroll patches, filtered device directory, udev isolation |
| Duplicate/silent audio | Actual sink uniqueness, app/capture/ROC routing, selected native/VNC mode, unwrapped clients bypassing managed scope |
| Clipboard forward bind failure | Legacy master, verified host/key prerequisites, server stale-socket recovery |
| Flake path absent | New peer-owned file may not be Git tracked; ask its owner to stage it |

Modules and host wiring are owned by their assigned workers; do not overwrite
peer files while updating this skill. No commits or activation without the
current task's permission.
