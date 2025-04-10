#!/usr/bin/env sh

privatedir="${0%/*}/private"
homeip=$(cat "${privatedir}/home/ip.txt")
sshport=$(cat "${privatedir}/home/sshport.txt")

waypipe --no-gpu \
    ssh -t -p ${sshport} minttea@${homeip} 'sway --unsupported-gpu'

