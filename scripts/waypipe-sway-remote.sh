#!/usr/bin/env sh
# waypipe-sway-remote.sh — remote entrypoint for waypipe-hosted sway sessions.
#
# Problem: when the laptop side dies (sleep, network drop, closed terminal),
# the remote `sway --unsupported-gpu` is killed without cleaning up its
# Wayland + sway-ipc sockets in $XDG_RUNTIME_DIR. The next session then picks
# a fresh socket name while processes in leftover terminals keep pointing at
# the dead one ("Failed to create window").
#
# This wrapper:
#   1. Pins the nested sway to one fixed display name (via WAYLAND_DISPLAY,
#      set by `waypipe --display`; defaults to wayland-waypipe standalone).
#   2. Before launch, removes that socket (+ .lock) only if nothing listens
#      on it, plus any dead sway-ipc sockets. Never touches live sockets and
#      never blanket-deletes wayland-* (the main session lives there too).
#   3. On EXIT/HUP/INT/TERM removes its own sockets the same gated way.
#
# Race note: check-then-remove is inherently racy, but the blast radius is
# confined to our fixed name and the atomic arbiter is the bind itself — a
# lost race ends in a loud sway startup failure, never a deleted live
# compositor socket (the liveness gate skips anything with a listener).
set -eu

DISPLAY_NAME="${WAYLAND_DISPLAY:-wayland-waypipe}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

case "$DISPLAY_NAME" in
  */*) WAYLAND_SOCK="$DISPLAY_NAME" ;;
  *) WAYLAND_SOCK="$RUNTIME_DIR/$DISPLAY_NAME" ;;
esac

is_live() {
  # $1 = socket path. True iff some process listens there right now.
  [ -S "${1:?}" ] && ss -xl 2>/dev/null | grep -qF " $1"
}

prune_if_dead() {
  # $1 = socket path. Remove it (and its .lock sidecar) only when dead.
  sock="${1:?}"
  if [ -e "$sock" ] && ! is_live "$sock"; then
    rm -f "$sock" "$sock.lock"
  fi
}

sweep_stale() {
  prune_if_dead "$WAYLAND_SOCK"
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

if is_live "$WAYLAND_SOCK"; then
  echo "waypipe-sway-remote: $WAYLAND_SOCK is already live; not starting a second nested sway" >&2
  exit 1
fi

exec sway --unsupported-gpu
