#!/usr/bin/env bash
# dictate — push-to-talk transcription with Whistle on the CPU.
#
#   dictate              toggle: start recording, or stop and copy the result
#   dictate file X.wav   transcribe an existing file and copy it
set -uo pipefail

rt="${XDG_RUNTIME_DIR:-/tmp}"
pidf="$rt/dictate.pid"
state="$rt/dictate.state"
wav="$rt/dictate.wav"
engine="${DICTATE_ENGINE:-$HOME/.local/share/whistle/needle}"
model="${DICTATE_MODEL:-$HOME/.local/share/whistle/whistle.cact}"
threads="${DICTATE_THREADS:-16}"
keywords="${DICTATE_KEYWORDS:-$HOME/.config/dictate/keywords.txt}"

set_state() { printf '%s' "${1:-}" > "$state"; }

transcribe() {
  local file="$1" out text
  local args=(--model "$model" --audio "$file" --threads "$threads")
  [[ -r $keywords ]] && args+=(--audio-keywords "$keywords")
  out="$("$engine" "${args[@]}" 2>/dev/null)" || return 1
  text="$(printf '%s' "$out" | jq -r '.text // ""' 2>/dev/null)" || return 1
  printf '%s' "$text"
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
      set_state transcribing
      text="$(transcribe "$wav")" || { set_state ""; exit 1; }
      copy "$text" || { set_state ""; exit 1; }
      set_state ""
      printf '%s\n' "$text"
    else
      pw-record --rate 16000 --channels 1 --format s16 --container wav "$wav" &
      echo $! > "$pidf"
      set_state recording
    fi
    ;;

  *)
    echo "usage: dictate [toggle|file <wav>]" >&2
    exit 2
    ;;
esac
