#!/usr/bin/env sh

waypipe --display wayland-waypipe \
	ssh -t -p 8108 minttea@desktop '/home/minttea/dotfiles/scripts/waypipe-sway-remote.sh'
