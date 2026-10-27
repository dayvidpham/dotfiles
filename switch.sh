#!/usr/bin/env bash

# --no-drain runs the rebuild without waiting for the GitHub runner pool to go
# idle. The rebuild restarts the user units, so the runner listener cancels any
# in-flight job on SIGTERM; use it when a cancelled job is cheaper than waiting.
no_drain=0
if [[ "${1:-}" = "--no-drain" ]]; then
   no_drain=1
   shift
fi

if [[ $# -eq 0 || "$1" = "home" ]]; then
   home-manager switch --flake . |& nom
elif [[ "$1" = "nixos" ]]; then
   if [[ "$no_drain" = 1 || "${SWITCH_NO_DRAIN:-0}" = 1 ]]; then
      echo 'NOTICE: drain skipped (--no-drain or SWITCH_NO_DRAIN=1); in-flight runner jobs will be cancelled.'
   elif command -v github-runner-drain >/dev/null 2>&1; then
      # Drain the runner pool first: the rebuild restarts the user units, and the
      # runner listener cancels an in-flight job on SIGTERM.
      if ! github-runner-drain; then
         echo 'ERROR: runner pool still busy after the drain timeout; rebuild aborted.'
         echo '       Re-run once the jobs finish, or force the rebuild with --no-drain.'
         exit 1
      fi
   else
      echo 'NOTICE: github-runner-drain not on PATH; rebuilding without draining the pool.'
   fi
   sudo nixos-rebuild switch --flake . |& nom
elif [[ $# -gt 1 ]]; then
   echo 'ERROR: Zero or one argument [--no-drain] [home|nixos] only, home if no arguments given'
fi
