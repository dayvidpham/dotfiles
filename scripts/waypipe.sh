#!/usr/bin/env sh

waypipe --no-gpu \
    ssh -t -p 8108 minttea@desktop 'sway --unsupported-gpu'
