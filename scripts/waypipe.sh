#!/usr/bin/env sh

# Let waypipe pick the remote display-socket name (random per run) instead of
# pinning --display: a random name cannot collide with a corpse left by a
# crashed run, which removes the need for a pre-clean ssh. That pre-clean also
# bypassed ssh ControlMaster ( -o ControlMaster=no -o ControlPath=none ), so it
# forced a fresh authentication on every launch. One connection only, so ssh can
# authenticate once and reuse its master.
#
# --no-gpu: block wayland-drm/linux-dmabuf over the wire. Without it, waypipe
# negotiates dmabufs against the desktop's GPU and the server connection process
# dies mid-negotiation (observed right after picking the NVIDIA render node),
# dropping the display and killing sway. Apps inside the nested sway still use
# the desktop's EGL; only the waypipe transport is affected.
waypipe --no-gpu ssh -t -p 8108 minttea@desktop \
	'/home/minttea/dotfiles/scripts/waypipe-sway-remote.sh'
