#!/usr/bin/env bash
# Diagnostic script for exit node connectivity issues
# Run via: ./vm-exec.sh "$(cat scripts/diagnose-exit-node.sh)"

set -x

echo "=== TAILSCALE STATUS ==="
tailscale status 2>&1

echo ""
echo "=== EXIT NODE SETTINGS ==="
tailscale status --json 2>/dev/null | jq '{ExitNodeStatus, CurrentTailnet, BackendState}' 2>&1

echo ""
echo "=== NETWORK ROUTES ==="
ip route show 2>&1

echo ""
echo "=== DNS CONFIGURATION ==="
cat /etc/resolv.conf 2>&1

echo ""
echo "=== TAILSCALE DNS STATUS ==="
tailscale dns status 2>&1 || echo "tailscale dns status not available"

echo ""
echo "=== TEST DNS WITHOUT EXIT NODE ==="
echo "Temporarily clearing exit node to test DNS..."
tailscale set --exit-node= 2>&1
sleep 2
echo "DNS test (no exit node):"
getent hosts api.anthropic.com 2>&1 || echo "DNS failed without exit node"
ping -c 1 -W 3 1.1.1.1 2>&1 || echo "ping failed without exit node"

echo ""
echo "=== RESTORE EXIT NODE AND TEST ==="
echo "Setting exit node to portal..."
tailscale set --exit-node=portal 2>&1
sleep 3
echo "DNS test (with exit node):"
getent hosts api.anthropic.com 2>&1 || echo "DNS failed with exit node"
ping -c 1 -W 3 1.1.1.1 2>&1 || echo "ping failed with exit node"

echo ""
echo "=== PORTAL NODE INFO ==="
tailscale status --json 2>/dev/null | jq '.Peer | to_entries[] | select(.value.HostName == "portal") | .value' 2>&1

echo ""
echo "=== CHECK IF PORTAL IS ADVERTISING EXIT NODE ==="
tailscale status --json 2>/dev/null | jq '.Peer | to_entries[] | select(.value.HostName == "portal") | {ExitNodeOption: .value.ExitNodeOption, ExitNode: .value.ExitNode, Online: .value.Online, OS: .value.OS, Relay: .value.Relay}' 2>&1

echo ""
echo "=== TAILSCALE NETCHECK ==="
tailscale netcheck 2>&1

echo ""
echo "=== IP ADDRESSES ==="
ip addr show tailscale0 2>&1
