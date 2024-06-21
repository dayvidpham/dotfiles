{ writeShellApplication
, runtimeShell
, grim
, slurp
, dmenu
, swappy
, wl-clipboard
, output-dir ? "$GRIM_DFEAULT_DIR"
, ...
}:
writeShellApplication rec {
  # Metadata
  name = "scythe";
  runtimeInputs = [ grim slurp dmenu swappy wl-clipboard ];

  text = ''
    #!${runtimeShell}
    OUT_DIR="${output-dir}"
        
    # If zero-length
    if [ -z "$OUT_DIR" ]; then
        OUT_DIR="$HOME/Pictures/Screenshots"
    fi

    # If not dir or does not exist
    if [ ! -d "$OUT_DIR" ]; then
        mkdir -p "$OUT_DIR"
    fi

    OUT_NAME=$(dmenu -p "$OUT_DIR/{input}-%date.png: " < /dev/null)

    OUT_PATH="$OUT_DIR/$OUT_NAME"

    grim -g "$(slurp)" - | swappy -f - -o - | tee "$OUT_PATH-$(date +%Y-%m-%dT%R:%S).png" | wl-copy -t image/png
  '';
}
