#!/usr/bin/env sh
set -eu

########################
# Defaults
WAYLAND_DISPLAY_NUM=$(printf '%s' "${WAYLAND_DISPLAY:-wayland-0}" | sed -e 's/^wayland-//')
XWAYLAND_LOG_FILE="${XDG_RUNTIME_DIR}/xwayland-satellite:${WAYLAND_DISPLAY_NUM}.log"

########################
# Try to use the DISPLAY that is already set,
# else try to match the WAYLAND_DISPLAY number

TRY_DISPLAY="${DISPLAY:-}"
TRY_DISPLAY="${TRY_DISPLAY#:}"

if [ -z "${TRY_DISPLAY}" ]; then
	TRY_DISPLAY="$WAYLAND_DISPLAY_NUM"
fi

# xwayland-satellite will try to set DISPLAY to our input,
# but it may already be taken, so must do additional parsing
xwayland-satellite ":$TRY_DISPLAY" >"$XWAYLAND_LOG_FILE" 2>&1 &
SATELLITE_PID="$!"

# Parse from log file
LINE_WITH_DISPLAY=""
ATTEMPTS=0
while [ "$ATTEMPTS" -lt 50 ]; do
	LINE_WITH_DISPLAY=$(grep -o 'Connected to Xwayland on :[[:alnum:].]*' "$XWAYLAND_LOG_FILE" 2>/dev/null | tail -n 1 || true)
	if [ -n "$LINE_WITH_DISPLAY" ]; then
		break
	fi

	if ! kill -0 "$SATELLITE_PID" 2>/dev/null; then
		echo "[ERROR] xwayland-satellite exited before reporting DISPLAY"
		wait "$SATELLITE_PID"
		exit 1
	fi

	ATTEMPTS=$((ATTEMPTS + 1))
	sleep 0.1
done

if [ -z "$LINE_WITH_DISPLAY" ]; then
	echo "[ERROR] Timed out waiting for xwayland-satellite to report DISPLAY"
	kill "$SATELLITE_PID" 2>/dev/null || true
	wait "$SATELLITE_PID" 2>/dev/null || true
	exit 1
fi

echo "[INFO] Extracted line with DISPLAY from $XWAYLAND_LOG_FILE: '$LINE_WITH_DISPLAY'"

DISPLAY="$(expr "$LINE_WITH_DISPLAY" : '.*\(:[0-9.]*\)$')"
if [ -z "$DISPLAY" ]; then
	echo "[ERROR] Failed to parse DISPLAY from xwayland-satellite log line"
	kill "$SATELLITE_PID" 2>/dev/null || true
	wait "$SATELLITE_PID" 2>/dev/null || true
	exit 1
fi

echo "[INFO] Extracted variable DISPLAY='$DISPLAY' from line"

echo "[INFO] Exporting DISPLAY, and updating D-Bus and systemd environment"

export DISPLAY
dbus-update-activation-environment --verbose --systemd DISPLAY

wait "$SATELLITE_PID"
