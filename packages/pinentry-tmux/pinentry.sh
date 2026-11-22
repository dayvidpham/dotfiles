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
#   - the tty is a live tmux pane: the most recently active attached client,
#     in any session (where the user last typed);
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
#
# Graphical requests that are not TUI panes get pinentry-qt instead: a window
# has its own surface, so it needs no popup and no tty at all. TUI panes keep
# the in-terminal popup, and display-less sessions fall back to it as before.
#
# The display check is deliberately conservative: pinentry-qt selects GUI mode
# from WAYLAND_DISPLAY/XDG_SESSION_TYPE and does not retry curses if Qt init
# fails, so require an actual display socket instead of trusting the variable.
#
# gpg-agent forwards the requester's WAYLAND_DISPLAY but not XDG_RUNTIME_DIR,
# and falls back to its own environment for anything the requester did not
# send. The agent's environment belongs to whichever session started it, and
# two compositors can use the same socket name in different runtime dirs (the
# desktop and the remote session both use wayland-1). So when the requesting
# terminal is known, its own display settings are authoritative: the prompt
# opens on the display that terminal is on, or on none if it has none.

# Replace the display variables with those of the oldest process on the
# requesting tty (the shell the terminal started).
adopt_requester_display() {
  local tty="${GPG_TTY:-}" pid entry
  [ -n "$tty" ] && [ -c "$tty" ] || return 0
  pid="$(ps -t "${tty#/dev/}" -o pid= --sort=start_time 2> /dev/null | head -n 1 | tr -d ' ')"
  [ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 0
  unset WAYLAND_DISPLAY DISPLAY
  while IFS= read -r -d '' entry; do
    case "$entry" in
      XDG_RUNTIME_DIR=* | WAYLAND_DISPLAY=* | DISPLAY=*) export "${entry?}" ;;
    esac
  done < "/proc/$pid/environ"
}

# Is a graphical session actually reachable from this process?
have_display() {
  if [ -n "${WAYLAND_DISPLAY:-}" ] &&
    [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY}" ]; then
    return 0
  fi
  if [ -n "${DISPLAY:-}" ]; then
    # DISPLAY is [host]:N[.screen]; only local servers have a socket here.
    local n="${DISPLAY##*:}"
    [ -S "/tmp/.X11-unix/X${n%%.*}" ] && return 0
  fi
  return 1
}

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

# gpg-agent forwards the requesting client's GPG_TTY in the session env, so a
# TUI-pane request can be recognised before pinentry starts. That matters
# because pinentry has to start early: its Assuan greeting is what unblocks
# the agent, so the backend cannot be chosen by waiting for OPTION ttyname.
tty_is_tmux_pane() {
  local tty="${GPG_TTY:-}" pane
  [ -n "$tty" ] || return 1
  while read -r pane; do
    [ "$pane" = "$tty" ] && return 0
  done < <(tmux list-panes -a -F '#{pane_tty}' 2> /dev/null)
  return 1
}

# Fall back to the persistent remote-session Wayland compositor when a
# tty-less request (pass-secret-service, ssh-agent) has neither an attached
# tmux client nor a desktop display.
adopt_remote_display() {
  local dir="${PINENTRY_REMOTE_RUNTIME_DIR:-/run/user/$(id -u)/remote}"
  if [ -S "$dir/wayland-1" ]; then
    export XDG_RUNTIME_DIR="$dir" WAYLAND_DISPLAY="wayland-1"
    return 0
  fi
  return 1
}

adopt_requester_display

# No server means no popup is possible: a graphical session still gets Qt,
# everything else stays transparent on the requested tty.
if ! resolve_tmux; then
  if have_display; then
    exec pinentry-qt "$@"
  fi
  if [ -z "${GPG_TTY:-}" ] && adopt_remote_display; then
    exec pinentry-qt "$@"
  fi
  exec pinentry-curses "$@"
fi

# Non-TUI graphical request: a Qt window needs neither a popup nor a tty.
# When GPG_TTY is empty (pass-secret-service, ssh-agent), prefer the most
# recently active tmux client if any client is attached; only use Qt when no
# tmux client can take the prompt.
if [ -n "${GPG_TTY:-}" ]; then
  if have_display && ! tty_is_tmux_pane; then
    exec pinentry-qt "$@"
  fi
elif [ -z "$(tmux list-clients -F '#{client_tty}' 2> /dev/null)" ]; then
  if have_display || adopt_remote_display; then
    exec pinentry-qt "$@"
  fi
fi

pane_rows() { tmux list-panes -a -F '#{pane_tty} #{session_name}' 2> /dev/null || true; }
client_rows() { tmux list-clients -F '#{client_tty} #{client_session} #{client_activity}' 2> /dev/null || true; }

is_pane_tty() {
  local want="$1" tty
  while read -r tty _; do
    [ "$tty" = "$want" ] && return 0
  done < <(pane_rows)
  return 1
}

is_client_tty() {
  local want="$1" tty
  while read -r tty _; do
    [ "$tty" = "$want" ] && return 0
  done < <(client_rows)
  return 1
}

# Print the most recently active attached client, in any session. tmux updates
# client_activity on input, so this is the terminal the user last typed in. It
# follows the user between terminals (the desktop and a remote session, say)
# even when the request comes from a pane in a session that only other
# terminals show, such as an agent committing in the background.
newest_client() {
  local tty activity best=-1 found=""
  while read -r tty _ activity; do
    if [ "${activity:-0}" -gt "$best" ]; then
      best="${activity:-0}"
      found="$tty"
    fi
  done < <(client_rows)
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

scratch="$(mktemp -d "${TMPDIR:-/tmp}/pinentry-tmux.XXXXXX")"
mkfifo "$scratch/in" "$scratch/out" "$scratch/tty" "$scratch/done"
popupPid=""
popupTty=""
pinentryPid=""
outPid=""

# Idempotent teardown: stop pinentry, close the popup, drop scratch files.
cleanup() {
  if [ -n "$pinentryPid" ]; then
    kill "$pinentryPid" 2> /dev/null || true
    wait "$pinentryPid" 2> /dev/null || true
    pinentryPid=""
  fi
  if [ -n "$outPid" ]; then
    kill "$outPid" 2> /dev/null || true
    wait "$outPid" 2> /dev/null || true
    outPid=""
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
    client="$(newest_client)" || true
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

# pinentry's user interface is the tty; stdio carries the Assuan protocol.
# FIFOs on stdin and stdout let us rewrite or inject OPTION ttyname (and
# absorb its OK reply so Assuan stays in lockstep) before handing stdout over
# to a direct cat relay for the rest of the session.
pinentry-curses "$@" < "$scratch/in" > "$scratch/out" &
pinentryPid=$!
exec 8<> "$scratch/in"
exec 7< "$scratch/out"

relay_assuan_reply() { # <echo: 1|0>
  local echo_reply="$1" reply
  while IFS= read -r reply <&7; do
    [ "$echo_reply" -eq 1 ] && printf '%s\n' "$reply"
    case "$reply" in
      OK | OK\ * | ERR | ERR\ *) return 0 ;;
    esac
  done
  return 1
}

start_out_relay() {
  cat <&7 &
  outPid=$!
  exec 7<&-
}

# Relay pinentry's initial Assuan greeting so gpg-agent sends its first line.
relay_assuan_reply 1 || exit 1

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
          start_out_relay
          printf '%s\n' "$line" >&8 || break
          ;;
        OPTION | OPTION\ *)
          printf '%s\n' "$line" >&8 || break
          relay_assuan_reply 1 || break
          ;;
        BYE | BYE\ *)
          decided=1
          start_out_relay
          printf '%s\n' "$line" >&8 || break
          ;;
        *)
          decided=1
          if ! decide_surface ""; then
            exit 1
          fi
          if [ -n "$popupTty" ]; then
            printf 'OPTION ttyname=%s\n' "$popupTty" >&8 || break
            relay_assuan_reply 0 || break
          fi
          start_out_relay
          printf '%s\n' "$line" >&8 || break
          ;;
      esac
    else
      printf '%s\n' "$line" >&8 || break
    fi
  elif [ "$rc" -gt 128 ]; then
    kill -0 "$pinentryPid" 2> /dev/null || break
  else
    break
  fi
done

exec 8>&-
wait "$pinentryPid" 2> /dev/null || true
pinentryPid=""
if [ -n "$outPid" ]; then
  wait "$outPid" 2> /dev/null || true
  outPid=""
fi
