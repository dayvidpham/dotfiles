#!/usr/bin/env bash
# dictate-status — waybar indicator for the dictation toggle.
#
# Prints one line of waybar JSON. Recording and transcribing states come from
# the pidfile and the state file the `dictate` script maintains.
rt="${XDG_RUNTIME_DIR:-/tmp}"
pidf="$rt/dictate.pid"
state="$rt/dictate.state"

if [[ -s $pidf ]] && kill -0 "$(<"$pidf")" 2>/dev/null; then
  printf '{"text":"<span color=\\"#f38ba8\\">●</span>","tooltip":"Recording — Mod+Ctrl+Space to stop","class":"recording"}\n'
  exit 0
fi

case "$(cat "$state" 2>/dev/null)" in
  transcribing)
    printf '{"text":"<span color=\\"#f9e2af\\">◌</span>","tooltip":"Transcribing…","class":"busy"}\n'
    ;;
  *)
    printf '{"text":"<span color=\\"#6c7086\\">○</span>","tooltip":"Dictation idle — Mod+Ctrl+Space to record","class":"idle"}\n'
    ;;
esac
