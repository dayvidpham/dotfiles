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
waypipe --display wayland-waypipe \
	ssh -t -p 8108 minttea@desktop '/home/minttea/dotfiles/scripts/waypipe-sway-remote.sh'
