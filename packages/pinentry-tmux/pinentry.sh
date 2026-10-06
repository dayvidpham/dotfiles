#!/usr/bin/env bash
# pinentry shim for gpg-agent.
#
# gpg-agent passes the requesting process' tty (GPG_TTY) to pinentry as
# `OPTION ttyname`. When that process is a TUI in tmux (opencode, lazygit,
# neovim :terminal, ...) the TUI and pinentry-curses share one pty: the TUI
# repaints over the dialog, keeps consuming keystrokes, and mouse reporting
# injects escape sequences into the same input stream, so the passphrase can
# never be entered and the sign operation times out.
#
# This shim opens a tmux popup, which has its own private pty, and rewrites
# `OPTION ttyname` to point pinentry at that pty. The popup client is chosen
# from the request:
#
#   - the tty is a live tmux pane: the most recently active attached client
#     of that pane's session, else any attached client;
#   - the tty is a tmux client tty: that client;
#   - the tty is a plain terminal: no popup, pinentry-curses uses the tty;
#   - the tty is empty or unusable (ssh-agent requests carry no tty): the
#     most recently active attached client, whatever terminal it is on.
#
# When no client can show a popup and the tty cannot carry the prompt, the
# shim fails fast with a message instead of drawing on a shared pty.
# gpg-agent invokes this, not the requester, so the tmux runtime dir and the
# client to show the popup on are resolved here instead of from the
# environment.

# gpg-agent runs under the systemd user manager, where TMUX_TMPDIR is unset.
# Resolve the persistent server: an explicit TMUX_TMPDIR first, then the login
# runtime dir (home-manager sets it for shells), then tmux's default.
resolve_tmux() {
  local root
  for root in "${TMUX_TMPDIR:-}" "/run/user/$(id -u)" /tmp; do
    [ -n "$root" ] || continue
    if TMUX_TMPDIR="$root" tmux list-sessions > /dev/null 2>&1; then
      TMUX_TMPDIR="$root"
      export TMUX_TMPDIR
      return 0
    fi
  done
  return 1
}

# No server means no popup is possible: stay transparent.
resolve_tmux || exec pinentry-curses "$@"

pane_rows() { tmux list-panes -a -F '#{pane_tty} #{session_name}' 2> /dev/null || true; }
client_rows() { tmux list-clients -F '#{client_tty} #{client_session} #{client_activity}' 2> /dev/null || true; }

is_pane_tty() {
  local want="$1" tty session
  while read -r tty session; do
    [ "$tty" = "$want" ] && return 0
  done < <(pane_rows)
  return 1
}

is_client_tty() {
  local want="$1" tty session activity
  while read -r tty session activity; do
    [ "$tty" = "$want" ] && return 0
  done < <(client_rows)
  return 1
}

session_for_pane() {
  local want="$1" tty session
  while read -r tty session; do
    if [ "$tty" = "$want" ]; then
      printf '%s\n' "$session"
      return 0
    fi
  done < <(pane_rows)
  return 1
}

# Print the most recently active attached client, optionally of one session.
newest_client() {
  local session="${1:-}" tty csession activity best=-1 found=""
  while read -r tty csession activity; do
    if { [ -z "$session" ] || [ "$csession" = "$session" ]; } &&
      [ "${activity:-0}" -gt "$best" ]; then
      best="${activity:-0}"
      found="$tty"
    fi
  done < <(client_rows)
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

# Print the client to show the popup on: the pane's session first, else the
# most recently active attached client.
pick_client() {
  local pane_tty="$1" session
  if session="$(session_for_pane "$pane_tty")" && [ -n "$session" ]; then
    newest_client "$session" && return 0
  fi
  newest_client
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pinentry-tmux.XXXXXX")"
mkfifo "$scratch/in" "$scratch/tty" "$scratch/done"
popupPid=""
popupTty=""
pinentryPid=""

# Idempotent teardown: stop pinentry, close the popup, drop scratch files.
cleanup() {
  if [ -n "$pinentryPid" ]; then
    kill "$pinentryPid" 2> /dev/null || true
    wait "$pinentryPid" 2> /dev/null || true
    pinentryPid=""
  fi
  if [ -n "$popupPid" ]; then
    # O_RDWR open never blocks, even if the popup already exited.
    if exec 9<> "$scratch/done" 2> /dev/null; then
      printf 'done\n' >&9 2> /dev/null || true
      exec 9>&-
    fi
    wait "$popupPid" 2> /dev/null || true
    popupPid=""
  fi
  if [ -n "$scratch" ]; then
    rm -rf "$scratch" 2> /dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Show a popup on the given client and wait for it to publish its tty; on
# success popupTty holds the popup's private pty. The popup command only
# needs to announce the tty and stay alive: pinentry-curses draws into that
# pty directly.
start_popup() {
  local client="$1"
  tmux display-popup -c "$client" \
    -e "PINENTRY_TTY_FIFO=$scratch/tty" \
    -e "PINENTRY_DONE_FIFO=$scratch/done" \
    -E 'printf "%s\n" "$(tty)" > "$PINENTRY_TTY_FIFO"; read -r _ < "$PINENTRY_DONE_FIFO"' &
  popupPid=$!

  popupTty="$(timeout 5 cat "$scratch/tty" 2> /dev/null || true)"
  case "$popupTty" in
    /dev/*) return 0 ;;
  esac

  popupTty=""
  kill "$popupPid" 2> /dev/null || true
  wait "$popupPid" 2> /dev/null || true
  popupPid=""
  return 1
}

# Decide the prompt surface for the requested tty. Sets popupTty when a popup
# is available; returns 1 when no surface can carry the prompt.
decide_surface() {
  local tty="$1" client=""
  if is_pane_tty "$tty"; then
    client="$(pick_client "$tty")" || true
  elif is_client_tty "$tty"; then
    client="$tty"
  elif [ -c "$tty" ]; then
    return 0
  else
    client="$(newest_client)" || true
  fi

  if [ -n "$client" ] && start_popup "$client"; then
    return 0
  fi

  printf 'pinentry-tmux: no prompt surface for tty "%s"; attach a tmux client or use a plain terminal\n' "$tty" >&2
  return 1
}

# pinentry's user interface is the tty; stdio carries the Assuan protocol. A
# fifo on stdin lets commands be rewritten on the way in while pinentry's
# stdout goes straight back to gpg-agent.
pinentry-curses "$@" < "$scratch/in" &
pinentryPid=$!
exec 8<> "$scratch/in"

# Wait for the first OPTION ttyname (or the first real command) before
# deciding, so the tty is known when the agent sends it.
decided=0
while :; do
  rc=0
  IFS= read -r -t 0.5 line || rc=$?
  if [ "$rc" -eq 0 ]; then
    if [ "$decided" -eq 0 ]; then
      case "$line" in
        'OPTION ttyname='*)
          decided=1
          if ! decide_surface "${line#OPTION ttyname=}"; then
            exit 1
          fi
          if [ -n "$popupTty" ]; then
            line="OPTION ttyname=$popupTty"
          fi
          ;;
        OPTION | OPTION\ *)
          : # wait for the ttyname option
          ;;
        *)
          decided=1
          if ! decide_surface ""; then
            exit 1
          fi
          ;;
      esac
    fi
    printf '%s\n' "$line" >&8 || break
  elif [ "$rc" -gt 128 ]; then
    kill -0 "$pinentryPid" 2> /dev/null || break
  else
    break
  fi
done

exec 8>&-
wait "$pinentryPid" 2> /dev/null || true
pinentryPid=""
