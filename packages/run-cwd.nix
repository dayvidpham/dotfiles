{ writeShellApplication
, runtimeShell
, sway
, jq
, ...
}:
writeShellApplication rec {
  # Metadata
  name = "run-cwd";
  runtimeInputs = [ sway jq ];

  # Script obtained from
  # https://www.reddit.com/r/swaywm/comments/xw49qv/comment/ir54lim/
  text = ''
    #!${runtimeShell}
    found=0
    if FOCUSED=$(swaymsg -t get_tree | jq -e '.. | select(.type?) | select(.focused) | .pid') && [ -n "$FOCUSED" ]; then
        # cwd of first-level child is usually more useful (e.g. shell proc forked from terminal emulator)
        # but fallback to the cwd of the focused app if no children procs
        for pid in $(cat "/proc/$FOCUSED/task"/*/children) $FOCUSED; do
            if cwd=$(readlink -e "/proc/$pid/cwd") && [ -n "$cwd" ]; then
                cd "$cwd" && found=1 && break
            fi
        done
    fi
    # No focused cwd (e.g. the first window in a fresh session): start in $HOME
    # rather than inheriting the compositor's cwd, which is / for a service.
    if [ "$found" = 0 ] && [ -n "''${HOME:-}" ] && [ -d "$HOME" ]; then
        cd "$HOME" || true
    fi
    exec "$@"
  '';
}
