#!/usr/bin/env bash
# Registration + launch entrypoint for the GitHub Actions runner container.
#
# The module passes the runtime through environment variables:
#   GITHUB_RUNNER_URL          organization URL (https://github.com/<org>)
#   GITHUB_RUNNER_NAME         runner name to register
#   GITHUB_RUNNER_TOKEN_FILE   file holding the runner PAT (--pat)
#   GITHUB_RUNNER_GROUP        optional runner group
#   GITHUB_RUNNER_LABELS       optional comma-separated extra labels
#   GITHUB_RUNNER_EPHEMERAL    1 to register per job
#   RUNNER_ROOT                host-visible runner root (install copy + state)
#   RUNNER_WORK                host-visible work directory
#
# The root is seeded from the image on first start so it holds the runner
# install in place (config.sh, run.sh, bin, externals) at a path the host
# shares with sibling containers.
set -euo pipefail

: "${GITHUB_RUNNER_URL:?GITHUB_RUNNER_URL is required}"
: "${GITHUB_RUNNER_NAME:?GITHUB_RUNNER_NAME is required}"
: "${GITHUB_RUNNER_TOKEN_FILE:?GITHUB_RUNNER_TOKEN_FILE is required}"

root="${RUNNER_ROOT:-/home/runner}"
work="${RUNNER_WORK:-$root/_work}"
ephemeral="${GITHUB_RUNNER_EPHEMERAL:-0}"

mkdir -p "$root" "$work/tmp"
cd "$root"

for f in config.sh run.sh run-helper.sh.template env.sh bin externals; do
  if [ ! -e "$root/$f" ] && [ -e "/home/runner/$f" ]; then
    cp -a "/home/runner/$f" "$root/"
  fi
done

token="$(cat "$GITHUB_RUNNER_TOKEN_FILE")"
stamp="$root/.pat-stamp"

need_config=0
if [ ! -f "$root/.runner" ]; then
  need_config=1
elif [ ! -f "$stamp" ] || ! printf '%s' "$token" | sha256sum | cmp -s - "$stamp"; then
  # The PAT rotated: re-register with --replace.
  need_config=1
fi

if [ "$need_config" = 1 ]; then
  args=(
    --unattended
    --replace
    --url "$GITHUB_RUNNER_URL"
    --pat "$token"
    --name "$GITHUB_RUNNER_NAME"
    --work "$work"
  )
  if [ -n "${GITHUB_RUNNER_GROUP:-}" ]; then
    args+=(--runnergroup "$GITHUB_RUNNER_GROUP")
  fi
  if [ -n "${GITHUB_RUNNER_LABELS:-}" ]; then
    args+=(--labels "$GITHUB_RUNNER_LABELS")
  fi
  if [ "$ephemeral" = 1 ]; then
    args+=(--ephemeral)
  fi
  ./config.sh "${args[@]}"
  printf '%s' "$token" | sha256sum > "$stamp"
fi

run_args=()
if [ "$ephemeral" = 1 ]; then
  run_args+=(--ephemeral)
fi

exec ./run.sh "${run_args[@]}"
