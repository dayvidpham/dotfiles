#!/usr/bin/env sh

# The fixed --display socket below is bound by the waypipe server, which does
# not unlink it first: a corpse file from a crashed run fails every later
# launch with EADDRINUSE. Drop it here (before the server starts) iff nothing
# listens on it. Absolute paths: non-interactive ssh has a minimal PATH.
#
# ControlMaster/ControlPath are disabled for this probe so it opens its own
# connection instead of creating/reusing the shared multiplexing master: the
# waypipe `ssh` below should own the master and its socket forwardings.
ssh -o ControlMaster=no -o ControlPath=none -p 8108 minttea@desktop 'sock=/run/user/1000/wayland-waypipe; /run/current-system/sw/bin/ss -xl | /run/current-system/sw/bin/grep -qF " $sock" || rm -f "$sock" "$sock.lock"'
# --no-gpu: block wayland-drm/linux-dmabuf over the wire. Without it, waypipe
# negotiates dmabufs against the desktop's GPU and the server connection process
# dies mid-negotiation (observed: it aborts right after picking the NVIDIA
# render node), which drops the display and sway dies with "Failed to dispatch
# remote Wayland display". Crossing two machines' GPU/driver stacks is the
# problem; the shm path is stable. Apps inside the nested sway (imv, browsers)
# still get the desktop's real EGL, since only the waypipe transport is affected.
waypipe --no-gpu --display wayland-waypipe \
	ssh -t -p 8108 minttea@desktop '/home/minttea/dotfiles/scripts/waypipe-sway-remote.sh'
