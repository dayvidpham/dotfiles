#!/usr/bin/env bash

if [[ $# -eq 0 || "$1" = "home" ]]; then
   home-manager switch --flake . |& nom
elif [[ "$1" = "nixos" ]]; then
   # Drain the runner pool first: the rebuild restarts the user units, and the
   # runner listener cancels an in-flight job on SIGTERM. The drain script is
   # shipped by the pool module (github-runner-drain); without it, say so and
   # proceed — the first rebuild that introduces the module cannot have it yet.
   if command -v github-runner-drain >/dev/null 2>&1; then
      if ! github-runner-drain; then
         echo 'ERROR: runner pool still busy after the drain timeout; rebuild aborted.'
         echo '       Re-run once the jobs finish, or force the rebuild with SWITCH_NO_DRAIN=1.'
         exit 1
      fi
   elif [[ "${SWITCH_NO_DRAIN:-0}" != 1 ]]; then
      echo 'NOTICE: github-runner-drain not on PATH; rebuilding without draining the pool.'
   fi
   sudo nixos-rebuild switch --flake . |& nom
elif [[ $# -gt 1 ]]; then
   echo 'ERROR: Zero or one argument [home|nixos] only, home if no arguments given'
fi
