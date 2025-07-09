#!/usr/bin/env sh

scripts_dir="${0%/*}"
. "${scripts_dir}/lib.sh"

waypipe \
	--no-gpu \
	--video "av1,hw,hwenc,hwdec,bpf=8e6" \
	ssh -t "minttea@desktop" 'sway --unsupported-gpu'
