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
# When the requested tty is a tmux pane this shim opens a tmux popup (which
# has its own private pty) and rewrites `OPTION ttyname` to point pinentry at
# that pty. Otherwise it is a transparent pass-through to pinentry-curses.
# gpg-agent invokes this, not the requester, so the tmux runtime dir and the
# client to show the popup on are resolved here instead of from the
# environment.

# gpg-agent runs under the systemd user manager, where TMUX_TMPDIR is unset.
# The persistent server's socket lives in the login runtime dir (home-manager
# sets TMUX_TMPDIR there for shells).
if [ -z "${TMUX_TMPDIR:-}" ]; then
  TMUX_TMPDIR="/run/user/$(id -u)"
  export TMUX_TMPDIR
fi

# No attached tmux client means no popup can be shown; stay out of the way.
if [ -z "$(tmux list-clients -F '#{client_tty}' 2>/dev/null || true)" ]; then
  exec pinentry-curses "$@"
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pinentry-tmux.XXXXXX")"
mkfifo "$scratch/in" "$scratch/tty" "$scratch/done"
popupPid=""
popupTty=""
popupTried=0
pinentryPid=""

# Idempotent teardown: stop pinentry, close the popup, drop scratch files.
cleanup() {
  if [ -n "$pinentryPid" ]; then
    kill "$pinentryPid" 2>/dev/null || true
    wait "$pinentryPid" 2>/dev/null || true
    pinentryPid=""
  fi
  if [ -n "$popupPid" ]; then
    # O_RDWR open never blocks, even if the popup already exited.
    if exec 9<>"$scratch/done" 2>/dev/null; then
      printf 'done\n' >&9 2>/dev/null || true
      exec 9>&-
    fi
    wait "$popupPid" 2>/dev/null || true
    popupPid=""
  fi
  rm -rf "$scratch" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

# Print the most recently active attached client of the session owning the
# given pane tty; fall back to any attached client. Fails when the tty is not
# a tmux pane or no client is attached.
pickClient() {
  local paneTty="$1" session="" client="" best=-1 t s a c
  while read -r t s; do
    if [ "$t" = "$paneTty" ]; then
      session="$s"
      break
    fi
  done < <(tmux list-panes -a -F '#{pane_tty} #{session_name}' 2>/dev/null || true)

  [ -n "$session" ] || return 1

  while read -r c s a; do
    if [ "$s" = "$session" ] && [ "${a:-0}" -gt "$best" ]; then
      best="${a:-0}"
      client="$c"
    fi
  done < <(tmux list-clients -F '#{client_tty} #{client_session} #{client_activity}' 2>/dev/null || true)

  if [ -z "$client" ]; then
    client="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -n 1 || true)"
  fi
  [ -n "$client" ] || return 1
  printf '%s\n' "$client"
}

# Show a popup and wait for it to publish its tty; on success popupTty holds
# the popup's private pty. The popup command only needs to announce the tty
# and stay alive: pinentry-curses draws into that pty directly.
startPopup() {
  local paneTty="$1" client
  client="$(pickClient "$paneTty")" || return 1

  tmux display-popup -c "$client" \
    -e "PINENTRY_TTY_FIFO=$scratch/tty" \
    -e "PINENTRY_DONE_FIFO=$scratch/done" \
    -E 'printf "%s\n" "$(tty)" > "$PINENTRY_TTY_FIFO"; read -r _ < "$PINENTRY_DONE_FIFO"' &
  popupPid=$!

  popupTty="$(timeout 5 cat "$scratch/tty" 2>/dev/null || true)"
  case "$popupTty" in
    /dev/*) return 0 ;;
  esac

  popupTty=""
  kill "$popupPid" 2>/dev/null || true
  wait "$popupPid" 2>/dev/null || true
  popupPid=""
  return 1
}

# pinentry's user interface is the tty; stdio carries the Assuan protocol. A
# fifo on stdin lets commands be rewritten on the way in while pinentry's
# stdout goes straight back to gpg-agent.
pinentry-curses "$@" < "$scratch/in" &
pinentryPid=$!
exec 8<>"$scratch/in"

# gpg-agent writes whole Assuan lines per write, so the timeout read never
# splits a line in practice; the timeout only exists to notice pinentry exit.
while :; do
  rc=0
  IFS= read -r -t 0.5 line || rc=$?
  if [ "$rc" -eq 0 ]; then
    case "$line" in
      'OPTION ttyname='*)
        if [ "$popupTried" -eq 0 ]; then
          popupTried=1
          startPopup "${line#OPTION ttyname=}" || true
        fi
        if [ -n "$popupTty" ]; then
          line="OPTION ttyname=$popupTty"
        fi
        ;;
    esac
    printf '%s\n' "$line" >&8 || break
  elif [ "$rc" -gt 128 ]; then
    kill -0 "$pinentryPid" 2>/dev/null || break
  else
    break
  fi
done

exec 8>&-
wait "$pinentryPid" 2>/dev/null || true
pinentryPid=""
