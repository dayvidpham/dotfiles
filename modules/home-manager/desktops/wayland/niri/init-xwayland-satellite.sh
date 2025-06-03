#!/usr/bin/env sh

########################
# Defaults
XWAYLAND_LOG_FILE="${XDG_RUNTIME_DIR}/xwayland-satellite:${WAYLAND_DISPLAY_NUM}.log"

########################
# Try to use the DISPLAY that is already set,
# else try to match the WAYLAND_DISPLAY number

TRY_DISPLAY="$DISPLAY"
WAYLAND_DISPLAY_NUM=$(echo "$WAYLAND_DISPLAY" | sed -e 's/wayland-//')

if [ -z "${TRY_DISPLAY}" ]; then
	TRY_DISPLAY="$WAYLAND_DISPLAY_NUM"
fi

# xwayland-satellite will try to set DISPLAY to our input,
# but it may already be taken, so must do additional parsing
xwayland-satellite ":$TRY_DISPLAY" >"$XWAYLAND_LOG_FILE" 2>&1 &

# Parse from log file
LINE_WITH_DISPLAY=$(grep -o 'Connected to Xwayland on :[[:alnum:]]*' XWAYLAND_LOG_FILE)
echo "[INFO] Extracted line with DISPLAY from $XWAYLAND_LOG_FILE: '$LINE_WITH_DISPLAY'"

DISPLAY="$(expr "$LINE_WITH_DISPLAY" : '.*\(:[0-9.]*\)$')"
echo "[INFO] Extracted variable DISPLAY='$DISPLAY' from line"

echo "[INFO] Exporting DISPLAY, and updating D-Bus and systemd envronment"

export DISPLAY
dbus-update-activation-environment --verbose --systemd DISPLAY
