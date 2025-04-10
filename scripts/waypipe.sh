#!/usr/bin/env sh

hidedir="${0%/*}/_hide"
homeip=$(cat "${hidedir}/home/ip.txt")
sshport=$(cat "${hidedir}/home/sshport.txt")

waypipe --no-gpu \
    ssh -t -p ${sshport} minttea@${homeip} 'sway --unsupported-gpu'

