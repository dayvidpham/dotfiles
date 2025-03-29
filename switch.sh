#!/usr/bin/env bash

if [[ $# -eq 0 || "$1" = "home" ]]; then
   home-manager switch --show-trace --flake . |& nom
elif [[ "$1" = "nixos" ]]; then
   sudo nixos-rebuild switch --show-trace --flake . |& nom
elif [[ $# -gt 1 ]]; then
   echo 'ERROR: Zero or one argument [home|nixos] only, home if no arguments given'
fi
