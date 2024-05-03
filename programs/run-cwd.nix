{ writeShellApplication
, runtimeShell
, sway
, jq
}:
writeShellApplication rec {
    # Metadata
    name = "run-cwd";
    runtimeInputs = [ sway jq ];
    text = ''
        #!${runtimeShell}
        FOCUSED=$(swaymsg -t get_tree | jq -e '.. | select(.type?) | select(.focused) | .pid');
        echo $FOCUSED
        if [ -n "$FOCUSED" ]; then
            # cwd of first-level child is usually more useful (e.g. shell proc forked from terminal emulator)
            # but fallback to the cwd of the focused app if no children procs
            for pid in $(cat "/proc/$FOCUSED/task"/*/children) $FOCUSED; do
                if cwd=$(readlink -e "/proc/$pid/cwd") && [ -n "$cwd" ]; then
                    cd "$cwd" && break
                fi
            done
        fi
        exec "$@"
    '';
}
