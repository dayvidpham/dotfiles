#!/usr/bin/env sh
# waypipe-sway-remote.sh — remote entrypoint for waypipe-hosted sway sessions.
#
# Problem: when the laptop side dies (sleep, network drop, closed terminal),
# the remote nested sway is killed without cleaning up the sockets it owns in
# $XDG_RUNTIME_DIR. Later terminals pointing at those dead sockets fail with
# errors like "Failed to create window".
#
# Ownership warning (learned the hard way): under `waypipe ssh`, the
# $WAYLAND_DISPLAY socket belongs to the waypipe *server* — sway connects to
# it as a nested Wayland client. This wrapper must NEVER create, delete, or
# gate on that socket: at wrapper startup the server may not have bound it
# yet, so even a liveness-gated prune can delete it out from under sway
# ("Could not connect to remote display"). Only *other* dead sockets are
# pruned here; the current session arbitrates its own display socket.
set -eu

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# The display socket of THIS session. Owned by waypipe server. Hands off.
case "${WAYLAND_DISPLAY:-}" in
  */*) CURRENT_SOCK="$WAYLAND_DISPLAY" ;;
  "" ) CURRENT_SOCK="" ;;
  *)   CURRENT_SOCK="$RUNTIME_DIR/$WAYLAND_DISPLAY" ;;
esac

is_live() {
  # $1 = socket path. True iff some process listens there right now.
  [ -S "${1:?}" ] && ss -xl 2>/dev/null | grep -qF " $1"
}

prune_if_dead() {
  # $1 = socket path. Remove it (and its .lock sidecar) only when dead.
  # Never touch the current session's display socket (see above).
  sock="${1:?}"
  if [ -n "$CURRENT_SOCK" ] && [ "$sock" = "$CURRENT_SOCK" ]; then return 0; fi
  if [ -e "$sock" ] && ! is_live "$sock"; then
    rm -f "$sock" "$sock.lock"
  fi
}

sweep_stale() {
  for sock in "$RUNTIME_DIR"/wayland-*; do
    case "$sock" in *.lock) continue ;; esac
    [ -S "$sock" ] || continue
    prune_if_dead "$sock"
  done
  for ipc in "$RUNTIME_DIR"/sway-ipc."$(id -u)".*.sock; do
    [ -e "$ipc" ] || continue
    prune_if_dead "$ipc"
  done
}

cleanup() {
  sweep_stale
}
trap 'cleanup' EXIT HUP INT TERM

sweep_stale

exec sway --unsupported-gpu
