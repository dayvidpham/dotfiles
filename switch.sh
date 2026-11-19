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

# Ask the built system which units a switch would stop or restart, and drain
# only when that touches the pool. A started or reloaded unit does not
# interrupt a job. Declarative microVMs restart on any guest change, so a guest
# change shows up here as a microvm@runner-vm-* restart. If the plan cannot be
# computed, assume the pool is affected.
runner_pool_affected() {
   local plan touched

   if ! plan=$(sudo "$1/bin/switch-to-configuration" dry-activate 2>&1); then
      echo 'WARNING: could not compute the switch plan (dry-activate failed); draining to be safe.' >&2
      return 0
   fi
   touched=$(grep -E '^would (stop|restart) the following units:' <<<"$plan" \
      | grep -oE '(runner-dispatcher[^ ,]*|microvm[^ ,]*@runner-vm-[^ ,]*|runner-vm\.slice)' \
      | sort -u)
   if [[ -n "$touched" ]]; then
      echo 'This switch stops or restarts runner pool units:'
      sed 's/^/   /' <<<"$touched"
      return 0
   fi
   return 1
}

# A rebuild does not start a unit that was stopped for the drain. Restart it on
# every exit path, including an aborted drain or a failed build or switch, so
# the pool never stays down after this script.
build_dir=
cleanup() {
   if [[ $dispatcher_was_active = 1 ]]; then
      echo 'Restarting the runner dispatcher.'
      sudo systemctl start runner-dispatcher.service
   fi
   [[ -n "$build_dir" ]] && rm -rf "$build_dir"
}
trap cleanup EXIT

if [[ $# -eq 0 || "$1" = "home" ]]; then
   home-manager switch --flake . |& nom
elif [[ "$1" = "nixos" ]]; then
   # Build first so the drain decision and the switch use the same system.
   # Pipe plain output into nom rather than `nom build`: that mode reads nix's
   # JSON log, which newer (Determinate) Nix extends with activity types nom
   # cannot parse.
   build_dir=$(mktemp -d)
   nix build ".#nixosConfigurations.$(hostname).config.system.build.toplevel" \
      --out-link "$build_dir/system" |& nom
   (( PIPESTATUS[0] == 0 )) || exit 1
   new_system=$(readlink -f "$build_dir/system")

   if [[ "$no_drain" = 1 || "${SWITCH_NO_DRAIN:-0}" = 1 ]]; then
      echo 'NOTICE: drain skipped (--no-drain or SWITCH_NO_DRAIN=1); in-flight runner jobs may be interrupted.'
   elif runner_pool_affected "$new_system"; then
      drain_runner_vms || exit 1
   else
      echo 'Runner pool units are unchanged by this switch; not draining.'
   fi
   # --no-reexec: with --store-path there is no flake to rebuild nixos-rebuild
   # from, so its self-update falls back to NIX_PATH's nixos-config, which is
   # flake.nix here and does not evaluate as a NixOS module.
   sudo nixos-rebuild switch --store-path "$new_system" --no-reexec
elif [[ $# -gt 1 ]]; then
   echo 'ERROR: Zero or one argument [--no-drain] [home|nixos] only, home if no arguments given'
fi
