#!/usr/bin/env sh

source ./lib.sh

waypipe --no-gpu \
    ssh -t -p ${ssh_port} minttea@${home_ip} 'sway --unsupported-gpu'

