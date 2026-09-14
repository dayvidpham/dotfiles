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

# Run sway with the user's config minus its session-management bits. The
# generated config ends with execs that import WAYLAND_DISPLAY/SWAYSOCK into the
# *host* systemd user manager and start/stop sway-session.target (plus restart
# kanshi, start polkit). Fine for a real login session; harmful here: this is a
# nested compositor inside the host, and those execs hijack the host's user
# session (clobbering WAYLAND_DISPLAY/SWAYSOCK, failing kanshi/waybar, and
# dragging graphical-session services into a display that dies with the tunnel).
#
# Also force Ghostty to a new instance. Its default gtk-single-instance=detect
# hands a launch to the already-running instance over the shared user D-Bus, so
# a terminal opened here would appear in the host's local session instead.
sway_config() {
  src="${XDG_CONFIG_HOME:-$HOME/.config}/sway/config"
  [ -f "$src" ] || return 1
  out="$RUNTIME_DIR/waypipe-sway.config"
  grep -vE '^[[:space:]]*(exec|exec_always)[[:space:]].*(dbus-update-activation-environment|systemctl --user|polkit-gnome-authentication-agent)' "$src" \
    | sed -E "s#(/bin/ghostty)(['[:space:]\"])#\1 --gtk-single-instance=false\2#g" \
    > "$out" || true
  printf '%s\n' "$out"
}

if cfg="$(sway_config)"; then
  exec sway --unsupported-gpu -c "$cfg"
fi

exec sway --unsupported-gpu
