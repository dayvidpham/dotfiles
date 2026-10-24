# One persistent remote desktop: VNC and Moonlight

## Status and contract

This documents the proposed repository configuration, **not an applied migration**.
The existing desktop services were reported active; no activation or live migration
has been performed. Client audio policy is **AWAITING HUMAN** and final audio / GPU
hardware acceptance remains outstanding.

Given a viewer disconnect, when another VNC or Moonlight viewer attaches, then it
should see the **same windows** in one persistent `remote-session` Sway session.
It should not create another compositor or terminate applications on disconnect.
The physical desktop remains niri, isolated from the headless session's input.

## Pieces (desktop)

| Unit | Role |
|---|---|
| `remote-session-compositor` | Sole headless Sway, private D-Bus, shared Firefox profile and runtime `/run/user/1000/remote` |
| `remote-session-vnc` | wayvnc captures that Sway; tailnet-only listener |
| `sunshine-spike` | Sunshine captures that same Sway using `capture=wlr`; NVIDIA NVENC encoding |
| `sunshine-evbridge` | Bridges only Sunshine's isolated uinput devices to Sway virtual input |
| `clip-peer-sync` | One headless text/PNG clipboard reconciler shared by both transports |

Sunshine derives its user, runtime directory and Wayland display from
`CUSTOM.services.remote-session`; it owns **neither a compositor nor an audio sink**.
Both capture paths use the shared display, not the physical niri display.

### GPU and input tradeoffs

- Sway renders with `gles2` on the RTX 4090 render node
  `/dev/dri/by-path/pci-0000:01:00.0-render`, with the headless backend and no
  libinput devices. A render node is shareable; no second DRM-master owner is created.
- VNC deliberately uses the **software capture/encoding baseline** (no wayvnc
  `-g`). NVIDIA's VA-API driver is decode-only; moving the compositor to NVIDIA
  does **not** give wayvnc a VA-API encoder. GPU-rendered apps and software VNC
  capture are different layers. VNC performance must be measured on hardware.
- Sunshine retains the CUDA-enabled build, NVENC, `capture=wlr` and driver library
  path. Do not add a `cap_sys_admin` wrapper: secure-exec ignores
  `LD_LIBRARY_PATH` and can break NVENC.
- VNC injects Wayland virtual input directly. Sunshine uinput devices match
  `libvirtualhid*`, are hidden from host libinput, and are read only through the
  filtered evbridge directory. Keep the evbridge rescan and scroll patches.

## Connections, exposure and resolution

```sh
remote-desktop                 # VNC attachment only, from flowX13
vncviewer desktop:5900          # direct tailnet VNC
moonlight-qt                   # keep the installed scaling wrapper
```

The VNC launcher no longer opens or stops clipboard tunnels. Closing either
viewer leaves Sway and its apps running. The installed Moonlight wrapper retains
`SDL_MOUSE_RELATIVE_SYSTEM_SCALE=1` for trackpad scaling; bypassing it with
`nix run nixpkgs#moonlight-qt` loses that setting.

wayvnc resolves the IPv4 address of `tailscale0` at start and refuses to bind if
it is absent. It never falls back to a wildcard address. VNC authentication is
disabled: tailnet WireGuard/device access supplies transport protection. Sunshine
still requires pairing; do not expose either service publicly. The optional
`tailnetOnly=false` VNC mode accepts loopback only and needs an SSH video tunnel.

There is one `HEADLESS-1` output, so resolution changes affect **all viewers**.
Moonlight's width/height/FPS request is applied by Sunshine's preparation hook on
**application launch**, not every connection or resume. VNC observes the shared
size rather than racing it with another resize policy. The last applied mode
persists across disconnect/resume until another launch/manual mode change or
compositor restart (configured baseline `1920x1080@60Hz`). There is no
per-disconnect reset: one client's disconnect must not undo another client's
mode. Sunshine has no supported one-stream cap; overlapping viewers share one
desktop, and additional viewers/resumes do not automatically resize it.

## Shared audio — client policy AWAITING HUMAN

The single persistent session sink remains **`remote_audio`**: shared-session
applications use `PULSE_SINK=remote_audio`, Sunshine explicitly sets
`audio_sink=remote_audio`, and the ROC sender reads `remote_audio.monitor`.
Sunshine defines no additional persistent session sink. It may manage temporary
internal virtual sinks/default routing as before; those are not the persistent
application/ROC target. Pinned-source verification confirmed that explicit audio
capture prefers the configured sink. Reusing Sunshine's reserved
`sink-sunshine-stereo` name for the persistent sink risks duplicate/unload behavior,
so that earlier proposal was rejected. The session still connects to the user's
PipeWire/Pulse runtime outside its private Wayland runtime directory.

**No client transport/default has been selected here.** Whether ROC remains
always-on, native Moonlight audio is selected, or an explicit transport switch is
used awaits the human decision. Do not enable two audible paths by assumption or
claim final no-echo/latency validation. Test VNC/ROC and native Moonlight audio only
under the selected policy. A same-machine Moonlight test also needs its playback
pinned to a real sink, not the captured null sink.

## Clipboard

The viewer-independent SSH clipboard service carries text and PNG for both VNC
and Moonlight. There is one reconciler for headless Sway plus the existing physical
niri `clip-sync` service. Do not add a Sunshine clipboard reconciler. See the
[clipboard guide](<remote-clipboard.md>) for lifecycle, prerequisites and migration.

## Migration — BEFORE activation

1. **Warn the user and save work first:** the old `sunshine-compositor` session's
   windows cannot migrate into another Sway process. They **will close** when
   switching configurations. Remote-session compositor changes can also restart
   its apps; viewer persistence is not persistence across a compositor restart.
2. Close old VNC/Moonlight viewers, then retire the old viewer-owned clipboard
   SSH master as described in the [clipboard migration](<remote-clipboard.md#migration-before-activation>).
   Closing the viewer alone might leave `~/.ssh/clip-%h` running.
3. Arrange verified SSH known-host trust and a usable key/agent for the new
   noninteractive user service before activation. Retain access independent of
   this remote desktop while reviewing and applying configuration.
4. Only after approval should the operator activate server/client changes and
   inspect the units below. The legacy `sunshine-compositor` should be absent;
   exactly one shared compositor and one headless reconciler should remain.

These are operator instructions, not commands run by the implementation worker.

## Checks (no activation)

```sh
nix eval .#checks.x86_64-linux.clipboard-tunnel.drvPath
nix eval .#checks.x86_64-linux.shared-remote-session.drvPath
nix build --no-link .#checks.x86_64-linux.clipboard-tunnel
nix build --no-link .#checks.x86_64-linux.shared-remote-session
nix flake check --no-build
```

The flake checks exercise configuration contracts and mocked clipboard tunnel
lifecycle; they **do not prove** real NVIDIA capture/NVENC, audio, input isolation,
network recovery or hardware clipboard interoperability.

## Hardware UAT (operator-run, after approved activation)

Read-only diagnostics:

```sh
systemctl is-active remote-session-compositor remote-session-vnc sunshine-spike sunshine-evbridge clip-peer-sync
systemctl --user is-active clipd clip-tunnel   # on flowX13
journalctl --user -u clip-tunnel -b            # on flowX13
journalctl -u sunshine-spike -b
nvidia-smi
```

Use the PID-named Sway IPC socket under `/run/user/1000/remote` for `swaymsg`
inspection; it is not the Wayland display socket. Inspect `get_tree`, `get_outputs`
and `get_inputs`; check one compositor process, sink uniqueness and NVENC logs.

| Given / when | Then should observe; should not observe |
|---|---|
| Open terminal/browser in VNC; attach Moonlight, then detach/reconnect either | Same windows/content and application PIDs; no second compositor |
| Launch application through Moonlight, then attach/resume/disconnect additional viewers | Both see launch-requested mode; resume does not reapply size, disconnect does not reset, no competing VNC resize |
| Copy text and PNG in each direction through each viewer | Same pasteable payload in shared apps; no feedback loop or duplicate reconciler |
| Dictation produces clipboard text on laptop | Paste reaches the same focused remote application in VNC and Moonlight |
| Selected audio policy: VNC/ROC and native Moonlight tests | Expected audible route, no duplication/echo, acceptable latency; mark pending until selection |
| Close all viewers, reconnect SSH/network, then reattach | Clipboard tunnel remains singleton and recovers without prompts/socket-bind failure; apps persist |
| Restart/crash capture process, then approved compositor failure test | Capture reconnects to live shared socket; compositor crash may lose windows, dependents recover without manual activation |
| Type/click/scroll with Moonlight/VNC while watching physical niri | Only shared session receives remote input; physical keyboard/mouse stay local; trackpad/wheel scaling correct |

Crash/restart tests are disruptive and must not be run before the user's explicit
approval. Record actual hardware results separately; an active unit is not proof
of end-to-end functionality.
