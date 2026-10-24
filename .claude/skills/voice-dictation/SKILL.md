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
| `modules/home-manager/services/dictated/dictated.js` | HTTP-over-Unix-socket daemon |
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
- **One daemon, ~2 GB RSS.** The model is 652 MB int8; ONNX Runtime arenas take
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

Runtime: `sherpa-onnx-node` borrowed from `pkgs.llm-agents.dsh` (the package the
Harness itself ships). That is the one non-obvious coupling in the feature — a
host without `dsh` fails here first. The shipped `libonnxruntime.so` is a CPU
build (no `libonnxruntime_providers_cuda.so`, no cuDNN), so `provider: 'cuda'`
cannot work without building our own runtime.

## Changing things

```nix
CUSTOM.services.dictated.threads  = 6;          # decode threads
CUSTOM.services.dictated.maxBytes = 67108864;   # 64 MiB ≈ 35 min
```

After changing the model, threads, or the daemon source:
`home-manager switch --flake .` then `systemctl --user restart dictated`.
The client needs no restart — it reconnects per press.

Decode is **superlinear** in clip length because each output token attends over
every encoder frame: 11 s → 0.32 s, 30 s → 1.0 s, 266 s → 20 s. There is no VAD;
the whole clip goes in as one utterance. If long-form dictation becomes a use
case, add sherpa-onnx `Vad` segmentation (30 s segments, join the texts) rather
than raising the cap.

## Debugging playbook

1. **Service**: `systemctl --user status dictated` and
   `journalctl --user -u dictated -n 50`. A duplicate shebang in the generated
   wrapper once produced `SyntaxError: Invalid or unexpected token` on line 2.
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
| Daemon crash-loops with `SyntaxError` | duplicate shebang in the generated wrapper | keep `dictated.js` shebang-free; nix adds one |
| Two daemons after a rename | old user unit still running | `systemctl --user stop <old>`, check `pgrep -af dictated` |

## Checklist before changing

- [ ] `nix flake check --no-build` passes.
- [ ] New files `git add`ed — flakes only see tracked paths.
- [ ] `home-manager switch` run, and `dictated` restarted if the daemon changed.
- [ ] Verified with `dictate file`, not only by pressing the key.
- [ ] No capture file reintroduced anywhere.
