#!/usr/bin/env bash

# --no-drain runs the rebuild without waiting for the GitHub runner pool to go
# idle. The rebuild restarts the user units, so the runner listener cancels any
# in-flight job on SIGTERM; use it when a cancelled job is cheaper than waiting.
no_drain=0
if [[ "${1:-}" = "--no-drain" ]]; then
   no_drain=1
   shift
fi

# The pool is the systemd + microvm@ runner pool, not the old podman
# containers. Stop the dispatcher gracefully (SIGTERM; its -drain-timeout is
# 90s and the unit's TimeoutStopSec is 120s), then wait for every microvm@ slot
# to power off. A job that runs past the dispatcher's drain keeps its slot
# alive, so the slot wait is the real drain.
dispatcher_was_active=0
drain_runner_vms() {
   local deadline=$(( SECONDS + ${RUNNER_DRAIN_TIMEOUT:-900} ))

   if systemctl is-active --quiet runner-dispatcher.service; then
      dispatcher_was_active=1
      echo 'Draining the microVM runner pool: SIGTERM the dispatcher; in-flight jobs finish.'
      if ! sudo systemctl stop runner-dispatcher.service; then
         echo 'ERROR: could not stop runner-dispatcher; rebuild aborted.' >&2
         return 1
      fi
   fi

   while systemctl list-units --no-legend --state=active,activating \
      'microvm@runner-vm-*.service' | grep -q .; do
      if (( SECONDS >= deadline )); then
         echo "ERROR: runner VM slots still active after ${RUNNER_DRAIN_TIMEOUT:-900}s; rebuild aborted." >&2
         echo '       Wait for the jobs to finish, or force the rebuild with --no-drain.' >&2
         return 1
      fi
      sleep 5
   done

   return 0
}

if [[ $# -eq 0 || "$1" = "home" ]]; then
   home-manager switch --flake . |& nom
elif [[ "$1" = "nixos" ]]; then
   if [[ "$no_drain" = 1 || "${SWITCH_NO_DRAIN:-0}" = 1 ]]; then
      echo 'NOTICE: drain skipped (--no-drain or SWITCH_NO_DRAIN=1); in-flight runner jobs may be interrupted.'
   else
      drain_runner_vms || exit 1
   fi
   sudo nixos-rebuild switch --flake . |& nom
   # A rebuild does not start a unit that was stopped for the drain.
   if [[ $dispatcher_was_active = 1 ]]; then
      sudo systemctl start runner-dispatcher.service
   fi
elif [[ $# -gt 1 ]]; then
   echo 'ERROR: Zero or one argument [--no-drain] [home|nixos] only, home if no arguments given'
fi
