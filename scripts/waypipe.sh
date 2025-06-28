#!/usr/bin/env sh

scripts_dir="${0%/*}"
. "${scripts_dir}/lib.sh"

waypipe --no-gpu \
	ssh -t "minttea@desktop" 'sway --unsupported-gpu'
