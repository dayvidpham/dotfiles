#!/usr/bin/env bash
# Pick the display environment a tmux CLIENT should use.
#
# The tmux-client-env hook snapshots each attached client's display variables
# under /run/user/<uid>/tmux-client-env, keyed by client tty. This picker lists
# the live clients (plus "auto", which means "this client's own environment")
# and previews the diff between the client's current target and the
# highlighted one. Selecting a client records an override for THIS client;
# "auto" removes it. Nothing is cached: overrides and snapshots only exist
# while the clients are attached.

set -euo pipefail

dir="/run/user/$(id -u)/tmux-client-env"
override_dir="$dir/overrides"
vars=(DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XAUTHORITY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE)

sock="${TMUX_SOCK:-}"
if [ -n "$sock" ]; then
  tmux() { command tmux -S "$sock" "$@"; }
fi

# The client tty is passed by the key binding (#{client_tty}); a client, not a
# pane, owns the display, and panes are shared between clients.
mode="pick"
target_arg=""
client="${1:-${TMUX_CLIENT:-}}"
if [ "${1:-}" = "--preview" ]; then
  mode="preview"
  target_arg="${2:-}"
  client="${3:-${TMUX_CLIENT:-}}"
fi
[ -n "$client" ] || {
  printf 'tmux-display-picker: missing client tty\n' >&2
  exit 2
}

snapshot_for() { printf '%s/%s.env' "$dir" "$(printf '%s' "$1" | tr '/' '_')"; }
override_for() { printf '%s/%s' "$override_dir" "$(printf '%s' "$1" | tr '/' '_')"; }

# The client's effective target: its override when that target still has a
# snapshot, otherwise its own environment.
effective_target() {
  local ctty="$1" pinned
  pinned="$(cat "$(override_for "$ctty")" 2>/dev/null || true)"
  if [ -n "$pinned" ] && [ -r "$(snapshot_for "$pinned")" ]; then
    printf '%s' "$pinned"
  else
    printf '%s' "$ctty"
  fi
}

# Print "VAR=value" for the tracked variables, sorted, from one snapshot.
dump_env() {
  local f="$1" v
  [ -r "$f" ] || return 0
  (
    # shellcheck disable=SC1090
    . "$f"
    for v in "${vars[@]}"; do
      printf '%s=%s\n' "$v" "${!v-}"
    done
  ) | sort
}

preview() {
  local target="$1" cur curfile newfile cur_label new_label
  cur="$(effective_target "$client")"
  case "$target" in
    auto) newfile="$(snapshot_for "$client")" ;;
    *) newfile="$(snapshot_for "$target")" ;;
  esac

  curfile="$(snapshot_for "$cur")"
  [ -r "$curfile" ] || curfile=/dev/null
  cur_label="current (${cur})"
  if [ "$target" = auto ]; then
    new_label="target (auto -> ${client})"
  else
    new_label="target (${target})"
  fi

  if [ ! -r "$newfile" ]; then
    printf '%s\n%s\n\n(no environment recorded for this client)\n' "--- $cur_label" "+++ $new_label"
    return 0
  fi

  tmux-env-diff --color=always \
    --current-label "$cur_label" \
    --target-label "$new_label" \
    "$curfile" "$newfile"
}

if [ "$mode" = "preview" ]; then
  preview "$target_arg"
  exit 0
fi

selection="$(
  {
    printf 'auto|this client (its own display)\n'
    tmux list-clients -F '#{client_tty}|#{client_session}' 2>/dev/null |
      while IFS='|' read -r ctty sess; do
        f="$(snapshot_for "$ctty")"
        [ -r "$f" ] || continue
        label="$(dump_env "$f" | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_CURRENT_DESKTOP)=' | paste -sd' ' -)"
        marker=""
        [ "$ctty" = "$(effective_target "$client")" ] && marker=' *'
        printf '%s|%s  %s  (%s)%s\n' "$ctty" "$sess" "$label" "$ctty" "$marker"
      done
  } | fzf --delimiter='|' --with-nth=1,2 \
    --height=100% --reverse --prompt='display for this client> ' \
    --preview-window='right,60%,wrap' \
    --preview "$0 --preview {1} '$client'"
)" || exit 0

[ -n "$selection" ] || exit 0

case "$selection" in
  auto | auto\|*)
    rm -f "$(override_for "$client")"
    tmux display-message -c "$client" 'display: this client (applies at next prompt)'
    ;;
  *)
    target="${selection%%|*}"
    mkdir -p "$override_dir"
    chmod 700 "$override_dir"
    printf '%s\n' "$target" > "$(override_for "$client").tmp"
    mv "$(override_for "$client").tmp" "$(override_for "$client")"
    tmux display-message -c "$client" "display: $target (applies at next prompt)"
    ;;
esac
