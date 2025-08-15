#!/usr/bin/env sh

scripts_dir="${0%/*}"
. "${scripts_dir}/lib.sh"

#--no-gpu \
#--video "av1,hw,hwenc,hwdec,bpf=8e6" \
waypipe \
	--remote-node="/etc/card-dgpu" \
	--video="av1,hw,bpf=8e6" \
	--debug \
	ssh -t "minttea@desktop" 'sway --unsupported-gpu'
