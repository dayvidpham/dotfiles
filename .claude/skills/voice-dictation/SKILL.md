---
name: voice-dictation
description: >-
  Push-to-talk dictation on this fleet: the `dictate` client, the `dictated`
  warm Parakeet daemon, the waybar indicator, and the FIFO audio path that keeps
  recordings off disk. Use this whenever you touch
  modules/home-manager/programs/dictate, modules/home-manager/services/dictated,
  the niri `Mod+Ctrl+Space` bind, or the waybar `custom/dictate` module; when
  changing the recognizer, model, thread count or recording cap; or when
  debugging “no transcript”, a daemon that will not start, a missing bar icon,
  no audio cue, or a recording that disappeared. Erring toward using it is fine.
---

# Voice dictation

## What the user sees

`Mod+Ctrl+Space` starts recording, pressing it again stops and transcribes, and
the text lands on the clipboard. Cues: rising = started, falling = stopped,
two-tone = copied. Waybar shows `○` idle, `●` recording, `◌` transcribing,
immediately left of the tray. There is no window and no automatic paste — the
user pastes with their terminal's paste binding (`Ctrl+Shift+V` in ghostty,
`wl-paste`, …).

## Architecture

```
Mod+Ctrl+Space
  └─ niri spawn → dictate toggle                     (bash, wrapped PATH)
       ├─ idle:      cue → mkfifo → pw-record --raw  ─┐
       │                  curl --data-binary @fifo ──┴─▶ /run/user/<uid>/dictated/socket
       └─ recording: SIGINT pw-record → curl EOF ───────▶ dictated.service
                                                          (Parakeet, warm)
                              text ◀── HTTP response ────┘
       └─ wl-copy → cue → clear state

waybar (1 Hz) → dictate-status → reads pidfile/state → ○ / ● / ◌
```

| Path | Role |
|---|---|
| `modules/home-manager/programs/dictate/dictate.sh` | client: toggle, capture, cues, clipboard |
| `…/dictate-status.sh` | waybar poller, one JSON line per second |
| `…/sounds/*.wav` | the three cues, shipped in `$out/share/dictate` |
| `…/default.nix` | packages the client, wraps PATH, enables the option |
| `…/services/dictated/main.go` | HTTP-over-Unix-socket daemon (Go) |
| `…/services/dictated/bridge.c` | C shim over the sherpa-onnx C API, so cgo never mirrors a sherpa struct |
| `…/default.nix` | model fetch, daemon package, systemd user unit |
| `users/minttea/home.nix` | `CUSTOM.programs.dictate.enable`, `CUSTOM.services.dictated.enable` |

State lives in `$XDG_RUNTIME_DIR`: `dictate.pid` (pid of `pw-record`; presence =
recording), `dictate.state` (`recording` / `transcribing` / empty), and
`dictate/` (FIFO + transcript, 0700). The daemon owns `$XDG_RUNTIME_DIR/dictated/`.

## Invariants

- **No audio on disk.** Capture is `pw-record --raw` into a FIFO; `curl` streams
  it to the daemon, which converts s16le → float in memory. Do not reintroduce a
  capture file — an earlier version left a 904 KB `capture.wav` behind after an
  aborted run. The client deletes that legacy path on start as a belt-and-braces.
- **The client is model-agnostic.** It only knows “POST raw PCM to a socket, read
  text”. Swapping recognizers is a `dictated` change, not a client change.
- **One daemon, ~1.5 GB RSS.** The model is 652 MB int8; ONNX Runtime arenas take
  the rest. Never run two instances (check for leftovers after renames).
- **Socket is `srw-------` inside a 0700 directory**, created by the daemon; the
  systemd unit passes `%t/dictated/socket` so it follows the uid.
- **64 MiB cap** (`maxBytes`) ≈ 35 minutes; above it the daemon destroys the
  request and curl exits 56 — the recording is lost, by design.

## The recognizer

Parakeet TDT 0.6B v2, int8, English-only, CC-BY-4.0 weights, fetched from
`csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8` with per-file SHA-256
pins in `services/dictated/default.nix`. Chosen over the bundle default
(SenseVoiceSmall) on measured accuracy:

| Model | LibriSpeech clean WER | Cold load | Note |
|---|---|---|---|
| Parakeet TDT 0.6B v2 | **1.52** | 2.2 s | English only, no keyword biasing |
| SenseVoiceSmall | ~3.1 | 0.6 s | strong zh/yue, weaker English |
| Whistle | 4.31 | 0.1 s | 17 MB, keyword biasing, 7 European languages |

The warm daemon is what makes Parakeet viable: cold, every press paid a 2.2 s
model load. Warm, 11 s of audio decodes in **0.32 s**.

Runtime: `pkgs.sherpa-onnx` (Apache-2.0) reached through `bridge.c`, which builds
the transducer config and calls the C API; cgo links `libsherpa-onnx-c-api.so`
with an RPATH and the binary records `NEEDED libsherpa-onnx-c-api.so`. The
library version follows the flake's nixpkgs, not `dsh` — that coupling is gone.
nixpkgs builds it against `pkgs.onnxruntime` (MIT, `onnxruntime_USE_CUDA=FALSE`,
`BUILD_SHARED_LIB=TRUE`), so there is no GPU path and no static archive: a static
build needs both packages rebuilt with `BUILD_SHARED_LIBS=OFF`.

## Changing things

```nix
CUSTOM.services.dictated.threads  = 6;          # decode threads
CUSTOM.services.dictated.maxBytes = 67108864;   # 64 MiB ≈ 35 min
```

After changing the model, threads, or the daemon source:
`home-manager switch --flake .` then `systemctl --user restart dictated`.
The client needs no restart — it reconnects per press.

Decode is **superlinear** in clip length because each output token attends over
every encoder frame: 11 s → 0.32 s, 30 s → 1.0 s, and 266 s took 20 s before
segmentation existed.

Silero VAD is **off by default in this config** (`CUSTOM.services.dictated.vad =
false`): it cost 0.45–0.63 s per short clip against 0.32–0.36 s without, and for
push-to-talk latency wins. Set `vad = true` to get silence trimming and
segmentation back; it then runs on **every** recording, in two modes:

- **Under `vadMinSeconds` (default 30)**: VAD finds the speech span and the clip
  is transcribed once, trimmed to that span plus 200 ms of padding. Silence is
  skipped without splitting the sentence, so punctuation is preserved.
- **Over the threshold**: the clip is cut at pauses and each segment recognised
  separately. That makes long audio faster and more accurate — 266 s of silence
  went from 20.4 s to 0.98 s, 55 s of speech transcribes in 1.9 s — at the cost
  of punctuation at each boundary: every segment is capitalised and closed as
  its own utterance (`Americans. Ask not.` instead of `Americans, ask not`).

The cost is per request, not per second of audio: it is the detector run over
the clip, which is why short dictation pays it most.

One C-API trap: `SherpaOnnxVoiceActivityDetectorAcceptWaveform` advances one
window per call. Feeding it a whole clip at once yields only the tail segment;
`bridge.c` feeds 512-sample windows in a loop.

## Debugging playbook

1. **Service**: `systemctl --user status dictated` and
   `journalctl --user -u dictated -n 50`. Startup logs are Go `log` lines
   (`dictated: ready on … (6 threads)`). A cgo link failure shows up at build
   time, not run time.
2. **Socket**: `ls -l $XDG_RUNTIME_DIR/dictated/socket` — should be `srw-------`.
   Missing means the daemon died before `listen()`.
3. **Daemon by hand**, no microphone needed:

   ```bash
   curl -sS --unix-socket "$XDG_RUNTIME_DIR/dictated/socket" \
     -H 'Content-Type: audio/wav' \
     --data-binary @clip.wav http://localhost/transcribe
   ```

   `/transcribe-raw` takes s16le mono 16 kHz instead of a WAV.
4. **Client by hand**: `dictate file clip.wav` exercises transcription and the
   clipboard without touching the mic.
5. **PATH independence**: `env -i PATH=/nonexistent XDG_RUNTIME_DIR=… \
   WAYLAND_DISPLAY=… dictate file clip.wav` must still work — both scripts are
   wrapped with `makeWrapper --prefix PATH`.
6. **Indicator**: `dictate-status` prints the exact JSON waybar consumes. If the
   glyph is missing but the JSON is right, waybar did not reload its config
   (`home-manager switch` only daemon-reloads the unit; restart the service).
7. **Stale state**: a dead pid in `dictate.pid` makes the next press a fresh
   start; the script clears leftovers, including legacy `capture.wav`.

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Press does nothing, no cue | `dictate` not on PATH for niri, or bind not loaded | check `command -v dictate`; `niri msg action load-config-file` |
| Cue plays, no text, no done chime | daemon down or socket missing | `systemctl --user restart dictated` |
| `curl: (56) … reset by peer` | recording exceeded `maxBytes` | raise the cap, or add VAD |
| Text on clipboard but bar never changed | waybar config not reloaded | `systemctl --user restart waybar` |
| `error while loading shared libraries: libsherpa-onnx-c-api.so` | RUNPATH lost, or the flake's sherpa changed | rebuild; the RPATH is set in `CGO_LDFLAGS` |
| `sherpa-onnx could not create the recognizer` | wrong `DICTATED_MODEL_DIR` or unreadable ONNX files | check the unit's `Environment` and the store path |
| Two daemons after a rename | old user unit still running | `systemctl --user stop <old>`, check `pgrep -af dictated` |

## Checklist before changing

- [ ] `nix flake check --no-build` passes.
- [ ] New files `git add`ed — flakes only see tracked paths.
- [ ] `home-manager switch` run, and `dictated` restarted if the daemon changed.
- [ ] Verified with `dictate file`, not only by pressing the key.
- [ ] No capture file reintroduced anywhere.
