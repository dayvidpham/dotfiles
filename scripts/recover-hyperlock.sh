#!/usr/bin/env sh

INSTANCE_ARG="$1"
if [ -z "${INSTANCE_ARG}" ]; then
    echo "[INFO] No Hyprland instance given, using default '--instance 0'"
    HYPR_INSTANCE="0"
else
    HYPR_INSTANCE="${INSTANCE_ARG}"
fi

hyprctl --instance ${HYPR_INSTANCE} 'keyword misc:allow_session_lock_restore 1'
hyprctl --instance ${HYPR_INSTANCE} 'dispatch exec hyprlock'
