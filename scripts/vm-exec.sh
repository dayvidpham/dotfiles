#!/usr/bin/env bash
# Execute commands in the openclaw-vm via QEMU Guest Agent
# Usage: ./vm-exec.sh "command to run"
# Example: ./vm-exec.sh "systemctl status tailscaled"

set -euo pipefail

SOCKET="${VM_SOCKET:-/var/lib/microvms/openclaw-vm/guest-agent.sock}"
CMD="${1:-echo hello}"

if [[ ! -S "$SOCKET" ]]; then
  echo "Error: Guest agent socket not found at $SOCKET" >&2
  echo "Is the VM running? Try: VM_SOCKET=/path/to/guest-agent.sock $0 \"$CMD\"" >&2
  exit 1
fi

# Execute command and get PID
response=$(echo "{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-c\",\"$CMD\"],\"capture-output\":true}}" | \
  socat -t5 - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

pid=$(echo "$response" | jq -r '.return.pid // empty')

if [[ -z "$pid" ]]; then
  echo "Error: Failed to execute command" >&2
  echo "Response: $response" >&2
  exit 1
fi

# Poll for completion
for i in {1..60}; do
  result=$(echo "{\"execute\":\"guest-exec-status\",\"arguments\":{\"pid\":$pid}}" | \
    socat -t5 - UNIX-CONNECT:"$SOCKET" 2>/dev/null)

  exited=$(echo "$result" | jq -r '.return.exited // false')

  if [[ "$exited" == "true" ]]; then
    exitcode=$(echo "$result" | jq -r '.return.exitcode // 0')

    # Decode base64 output
    stdout=$(echo "$result" | jq -r '.return."out-data" // empty' | base64 -d 2>/dev/null || true)
    stderr=$(echo "$result" | jq -r '.return."err-data" // empty' | base64 -d 2>/dev/null || true)

    [[ -n "$stdout" ]] && echo "$stdout"
    [[ -n "$stderr" ]] && echo "$stderr" >&2

    exit "$exitcode"
  fi

  sleep 0.5
done

echo "Error: Command timed out" >&2
exit 124
