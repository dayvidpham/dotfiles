#!/usr/bin/env bash
# dictate — push-to-talk transcription with Whistle on the CPU.
#
#   dictate              toggle: start recording, or stop and copy the result
#   dictate file X.wav   transcribe an existing file and copy it
set -uo pipefail
umask 077

rt="${XDG_RUNTIME_DIR:-/tmp}"
capture="$rt/dictate"
pidf="$rt/dictate.pid"
state="$rt/dictate.state"
fifo="$capture/pcm"
result="$capture/result.txt"
curlpid="$capture/curl.pid"
socket="${DICTATE_SOCKET:-$rt/dictated/socket}"
self="$(readlink -f "${BASH_SOURCE[0]}")"
sounds="${DICTATE_SOUNDS:-$(dirname "$self")/../share/dictate}"

# A soft cue so you know the toggle landed without looking at the bar.
bloop() {
  local file="$sounds/$1.wav"
  [[ -r $file ]] || return 0
  pw-play "$file" >/dev/null 2>&1 &
}

set_state() { printf '%s' "${1:-}" > "$state"; }

# The daemon holds the recognizer warm; audio goes over a Unix socket and is
# never written anywhere but the tmpfs capture below, which is removed after use.
transcribe() {
  local file="$1"
  [[ -S $socket ]] || { echo "dictate: daemon socket missing at $socket" >&2; return 1; }
  curl -sS --max-time 300 --unix-socket "$socket" \
    -H 'Content-Type: audio/wav' --data-binary "@$file" \
    http://localhost/transcribe || return 1
}

copy() {
  [[ -n "$1" ]] || return 1
  printf '%s' "$1" | wl-copy
}

case "${1:-toggle}" in
  file)
    shift
    text="$(transcribe "${1:?usage: dictate file <wav>}")" || { echo "dictate: transcription failed" >&2; exit 1; }
    copy "$text"
    printf '%s\n' "$text"
    ;;

  toggle)
    if [[ -s $pidf ]] && kill -0 "$(<"$pidf")" 2>/dev/null; then
      pid="$(<"$pidf")"
      kill -INT "$pid" 2>/dev/null
      while kill -0 "$pid" 2>/dev/null; do sleep 0.05; done
      rm -f "$pidf"
      bloop stop
      set_state transcribing
      # pw-record closing the FIFO is what ends curl's upload.
      if [[ -s $curlpid ]]; then
        while kill -0 "$(<"$curlpid")" 2>/dev/null; do sleep 0.05; done
      fi
      text="$(cat "$result" 2>/dev/null)"
      rm -f "$fifo" "$result" "$curlpid"
      copy "$text" || { set_state ""; exit 1; }
      bloop done
      set_state ""
      printf '%s\n' "$text"
    else
      mkdir -p -m 700 "$capture"
      # Drop anything a previous recording left behind, including audio written
      # by an older version of this script that captured to a file.
      rm -f "$fifo" "$result" "$curlpid" "$capture/capture.wav"
      mkfifo -m 600 "$fifo"
      bloop start
      # curl reads the FIFO and streams it to the daemon as the capture is
      # written, so the audio only ever exists in pipe buffers.
      curl -sS --max-time 2400 --unix-socket "$socket" \
        -H 'Content-Type: audio/x-raw' --data-binary "@$fifo" \
        "http://localhost/transcribe-raw" > "$result" 2>/dev/null &
      echo $! > "$curlpid"
      pw-record --raw --rate 16000 --channels 1 --format s16 "$fifo" &
      echo $! > "$pidf"
      set_state recording
    fi
    ;;

  *)
    echo "usage: dictate [toggle|file <wav>]" >&2
    exit 2
    ;;
esac
