---
name: remote-desktop
description: >-
  Running remote-desktop and game-streaming sessions on this NixOS host — the
  persistent headless-sway + wayvnc "remote-session" and the headless-sway +
  Sunshine/Moonlight setup: GPU render/encode selection, input injection, audio
  routing, resolution matching, and the DRM/seat/profile constraints that shape
  all of it. Use whenever you work on modules/nixos/services/remote-session or
  modules/nixos/services/sunshine, add or modify a headless Wayland session,
  wire input or audio into a remote session, pick a GPU for capture/encode, or
  debug a stream (no video, no audio, no input, wrong resolution, latency, a
  service that fails on rebuild). Erring toward using it is fine.
---

# Remote desktop & streaming sessions

Two independent, additive remote-access paths on one host. The physical desktop
is **niri** (on the tty). The remote sessions are **headless sway** compositors
that never touch the physical GPU outputs — so they can't fight niri for DRM
master.

```
Physical desktop (niri)  ── DRM master on card0 (RTX 4090) + card1 (AMD iGPU)
                            monitors DP-1/2/3 on card0

remote-session (wayvnc)                       sunshine (Moonlight)
  headless sway                                 headless sway
  WLR_RENDER_DRM_DEVICE = renderD129 (iGPU)     WLR_RENDER_DRM_DEVICE = renderD128 (4090)
  capture/encode: wayvnc (VA-API, iGPU)         capture: Sunshine (capture=wlr)
  input: wayvnc virtual pointer/keyboard        encode: NVENC (4090)
  audio: remote_audio null sink → roc-send      input: evbridge (evdev → wlr virtual)
  XDG_RUNTIME_DIR=/run/user/1000/remote         audio: sink-sunshine-stereo null sink
  tailnet-only (wayvnc binds the tailnet IP)    XDG_RUNTIME_DIR=/run/user/1000/sunshine
```

Both get: a private D-Bus bus, the user's real sway config (bar + keybindings),
and a dedicated Firefox profile.

## Hardware / GPU map

- `card0` = RTX 4090 (nvidia, renderD128) — drives the physical monitors.
- `card1` = AMD Raphael iGPU (amdgpu, renderD129) — no outputs; free for rendering.
- **Card node** (`/dev/dri/cardN`) — display/scanout; can be DRM master; exclusive.
- **Render node** (`/dev/dri/renderDN`) — render/compute only; shareable.
- **VA-API encoder**: only the **iGPU** (Mesa radeonsi). `nvidia-vaapi-driver` is
  **decode-only** → the 4090 cannot VA-API-encode.
- **NVENC**: only if Sunshine is built with CUDA (see below).

## The constraints that shape everything

1. **DRM master is exclusive — one compositor per card.** niri owns card0/card1, so
   a second compositor must use `WLR_BACKENDS=headless` (no card at all), never the
   DRM backend. `sway --unsupported-gpu` is only a wlroots gate; it is **not**
   software rendering — the renderer is still `gles2` on a render node.
2. **Render on a render node; the dmabuf *feedback scanout* tranche needs a card.**
   `WLR_RENDER_DRM_DEVICE=<render node>` gives GPU rendering with no card.
   `zwp_linux_dmabuf_v1` is still advertised on headless; wlroots logs
   `Failed to get backend DRM FD` when building per-surface feedback because a
   headless output has no KMS device — **cosmetic** (there's nothing to scan out to).
3. **Two encoder worlds.** wayvnc/neatvnc hardware-encode via **VA-API only**
   (`h264_vaapi`) → the iGPU. Sunshine encodes via **NVENC** → the 4090, but only
   with a CUDA-enabled build and without a capability wrapper.
4. **Input injection differs.** wayvnc uses Wayland virtual-input protocols (no
   kernel devices, no seat → clean, no host leak). Sunshine uses **uinput** (kernel
   devices that land on seat0 → the host desktop would receive them) → needs udev
   isolation plus a bridge.
5. **Firefox locks a profile to one running instance** → concurrent sessions each
   need their own profile (or Firefox Sync for shared data).
6. **Seat0.** `LIBSEAT_BACKEND=noop` hardcodes the seat name to `"seat0"`, the same
   seat as the host — a libinput-based headless compositor would see the host's
   devices, and vice-versa. Prefer Wayland virtual-input protocols instead of libinput.

## Per-layer recipe

### Headless compositor
- Env: `WLR_BACKENDS=headless`, `WLR_RENDERER=gles2`,
  `WLR_RENDER_DRM_DEVICE=<render node>`, `WLR_RENDERER_ALLOW_SOFTWARE=1`,
  `WLR_LIBINPUT_NO_DEVICES=1` (reads no `/dev/input`), a dedicated `XDG_RUNTIME_DIR`
  (socket names collide otherwise).
- **`Type=notify` readiness** (see the `systemd-services` skill): wrap sway,
  background it, wait until the Wayland socket is *listening*, `systemd-notify --ready`,
  then `wait`. Dependents use only `After=`/`Requires=` — no polling.
- Reuse the user's sway config, filtered like `remote-session` does (strip `exec*`
  lines touching `systemctl --user` / `dbus-update-activation-environment` / polkit;
  `sed` ghostty to `--gtk-single-instance=false`), and append `exec waybar`. Put the
  user profile on `PATH`/`XDG_DATA_DIRS` so exec'd apps resolve.
- **`pkgs.dbus` must be on the compositor's PATH**: the nixpkgs sway wrapper runs
  `dbus-run-session` when there's no bus env/`$XDG_RUNTIME_DIR/bus`, and that execs
  `dbus-daemon` by name (otherwise it crash-loops). This also gives the session its
  private bus.

### Capture + encode
- **wayvnc**: screencopy capture; `-g` for dmabuf; VA-API encode on the render node.
- **Sunshine**: `capture = wlr`, `output_name = HEADLESS-1`, `encoder = nvenc`,
  `adapter_name = /dev/dri/renderD128`.
  - **nixpkgs `sunshine` is built with CUDA off** (`SUNSHINE_ENABLE_CUDA=false`), so
    NVENC is absent and surfaces as `Couldn't scale frame: Invalid argument`. Override:
    `pkgs-unstable.sunshine.override { cudaSupport = true; cudaPackages = pkgs-unstable.cudaPackages; }`
    (pkgs-unstable also carries the GHSA-fp6g-27w5-489j fix).
  - **No `cap_sys_admin` security wrapper.** `capture=wlr` doesn't need it, and a
    file-capability binary runs in glibc **secure-exec** mode, which makes the loader
    ignore `LD_LIBRARY_PATH` → `Cannot load libcuda.so.1`. NVENC also needs
    `LD_LIBRARY_PATH=/run/opengl-driver/lib`.

### Input
- **Preferred (wayvnc model)**: the compositor advertises `zwlr_virtual_pointer_v1` /
  `zwp_virtual_keyboard_v1`; the capture server injects through them. No seat, no leak.
- **Sunshine (uinput) model**:
  1. Sunshine creates `libvirtualhid Keyboard` / `Mouse` / `Mouse (Absolute)`
     (vendor `1209`, **no `ID_VENDOR_ID`/`ID_MODEL_ID`**) → match in udev with
     `ATTRS{name}=="libvirtualhid*"`.
  2. udev: `ENV{LIBINPUT_IGNORE_DEVICE}="1"` (host desktop ignores them) **and**
     `SYMLINK+="sunshine-evdev/%k"` into a filtered input dir.
  3. `evbridge` (github `atassis/evbridge`; **not in nixpkgs**, build from source)
     reads that dir and re-emits via wlr virtual input. Needs the `input` group, a
     pre-created dir, and must wait for the compositor socket.
  4. evbridge fixes (in `packages/evbridge.nix`): scroll is inverted and unscaled
     (negate vertical, ~×20); it scans the input dir only once at startup (patch the
     500 ms timer to re-scan, else lazily-created pointer devices are missed).

### Audio
- Create a persistent PipeWire null sink (drop-in in `services.pipewire.configPackages`
  with `restartTriggers`, like `remote_audio`).
- **Sunshine sets the default sink to its *own* sink (`sink-sunshine-stereo`) and
  captures that.** So name your null sink `sink-sunshine-stereo`, route apps there
  (`PULSE_SINK=sink-sunshine-stereo`), and set `audio_sink = sink-sunshine-stereo`.
  Give the session `PULSE_SERVER=unix:/run/user/1000/pulse/native`.
- remote-session instead routes apps to `remote_audio`, whose monitor `roc-send` streams.
- **Same-machine client/host gotcha:** Sunshine moves the *default* sink, so a
  Moonlight client running on the host has its own audio output follow the default
  into the silent null sink (and be re-captured → feedback) → the client "has no
  audio" even though it's transmitted. Only affects local testing; a client on
  another machine outputs to its own device. Locally, pin the client's output:
  `SDL_AUDIODRIVER=pulseaudio PULSE_SINK=<real host sink> moonlight-qt`, or
  `pactl move-sink-input <id> <real host sink>`.

### Resolution matching (Sunshine)
- `global_prep_cmd = [{"do":"<set>","undo":"<reset>"}]`; the set script runs
  `swaymsg output HEADLESS-1 mode ${SUNSHINE_CLIENT_WIDTH}x${SUNSHINE_CLIENT_HEIGHT}@${SUNSHINE_CLIENT_FPS}Hz`
  (Sunshine exports `SUNSHINE_CLIENT_*`). `swaymsg` needs the **PID-named** socket →
  discover `$XDG_RUNTIME_DIR/sway-ipc.*.sock`. Applied **per connection**, not on live
  window resize.

## Pitfalls quick table

| Symptom | Cause | Fix |
|---|---|---|
| `dbus-run-session: failed to execute message bus daemon` | sway wrapper needs `dbus-daemon` on PATH | add `pkgs.dbus` to runtimeInputs |
| `Couldn't scale frame: Invalid argument` | nixpkgs sunshine built without CUDA | `cudaSupport = true` |
| `Cannot load libcuda.so.1` | cap wrapper → secure-exec ignores `LD_LIBRARY_PATH` | drop the cap wrapper; add `/run/opengl-driver/lib` |
| `Failed to get backend DRM FD` | headless output has no KMS device | cosmetic (feedback scanout tranche) |
| no mouse in stream | evbridge scanned before Sunshine created the pointer | patch evbridge to re-scan |
| scroll inverted / too slow/fast | evdev↔wl axis sign and scale | negate vertical, scale ~×20 in evbridge |
| "Firefox already open elsewhere" | shared profile lock | dedicated profile (or Sync) |
| no audio | capturing a sink the apps don't play into | name the sink `sink-sunshine-stereo`, `PULSE_SINK` there |
| service fails on rebuild (`ENOENT` / `NoCompositor`) | startup race | `ExecStartPre` waits; see `systemd-services` skill |
| `nix eval` "path does not exist" | module not git-tracked | `git add` it |
| moonlight-qt ~10–25 s startup | SDL GPU/HDR probing + `xdg-desktop-portal` `NoReply` (pipewire restarts can strand the portal's PipeWire handle) | restart the portal; install moonlight-qt rather than `nix run` |

## Verifying a session

```bash
systemctl is-active sunshine-compositor sunshine-spike sunshine-evbridge   # or remote-session-*
S=$(ls /run/user/1000/sunshine/sway-ipc.*.sock|head -1)
SWAYSOCK=$S swaymsg -t get_inputs        # wlr_virtual_pointer_v1 AND wlr_virtual_keyboard_v1
SWAYSOCK=$S swaymsg -t get_outputs       # HEADLESS-1 size
pactl list short sinks | grep sunshine    # sink exists
pactl list short source-outputs           # application.name="sunshine" capturing the monitor
pactl list short sink-inputs              # the app is on the sink
journalctl -u sunshine-spike | grep -iE 'nvenc|opus|encoder'
nvidia-smi                                # C+G / NVE engine when encoding
```

Debugging order for "no X": **service active? → compositor socket + output → capture
server connected → encoder chosen → input devices present → audio sink + capture.**

## Repo conventions & references

- Modules: `modules/nixos/services/<name>/default.nix`, options under `CUSTOM.services.*`,
  imported in `modules/nixos/services/default.nix`; host wiring in
  `hosts/desktop/configuration.nix`. Packages: `packages/*.nix` via `pkgs-unstable.callPackage`.
- Commits: `git agent-commit` (signed, non-interactive). Track work in Beads.
- For readiness/races/ordering, read the **`systemd-services`** skill.
- Key files: `modules/nixos/services/remote-session/`, `modules/nixos/services/sunshine/`,
  `packages/evbridge.nix`, `packages/evbridge-rescan.patch`.

## Open / known

- Sunshine's audio sink name collides with Sunshine's own (two `sink-sunshine-stereo`);
  works but fragile.
- Firefox profile *data* isn't shared across sessions (needs Sync or a seeded copy).
- Desktop flicker on the physical niri session — separate issue, not the remote path.
