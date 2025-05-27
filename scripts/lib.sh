#!/usr/bin/env sh

export hide_dir="${0%/*}/_hide"
export home_ip=$(cat "${hide_dir}/home/ip.txt")
export ssh_port=$(cat "${hide_dir}/home/ssh_port.txt")

