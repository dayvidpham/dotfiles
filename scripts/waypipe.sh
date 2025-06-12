#!/usr/bin/env sh

scripts_dir="${0%/*}"
. "${scripts_dir}/lib.sh"

waypipe --no-gpu \
    ssh -t -p "${ssh_port}" "minttea@${home_ip}" 'sway --unsupported-gpu'
