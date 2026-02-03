#!/usr/bin/env bash
# Diagnostic script for tailscale autoconnect issues
# Run via: ./vm-exec.sh "$(cat scripts/diagnose-tailscale.sh)"

echo "=== TAILSCALE STATUS ==="
tailscale status 2>&1

echo ""
echo "=== TAILSCALED-AUTOCONNECT SERVICE STATUS ==="
systemctl status tailscaled-autoconnect --no-pager 2>&1

echo ""
echo "=== TAILSCALED-AUTOCONNECT LOGS ==="
journalctl -u tailscaled-autoconnect -b --no-pager 2>&1

echo ""
echo "=== TAILSCALED SERVICE STATUS ==="
systemctl status tailscaled --no-pager 2>&1

echo ""
echo "=== TAILSCALED LOGS (last 50 lines) ==="
journalctl -u tailscaled -b --no-pager | tail -50

echo ""
echo "=== AUTH KEY FILE EXISTS? ==="
ls -la /run/credentials/tailscaled.service/ 2>&1

echo ""
echo "=== SYSTEMD UNIT FILE FOR AUTOCONNECT ==="
systemctl cat tailscaled-autoconnect 2>&1

echo ""
echo "=== NETWORK INTERFACES ==="
ip addr show 2>&1

echo ""
echo "=== DNS RESOLUTION TEST ==="
getent hosts hs0.vpn.dhpham.com 2>&1 || echo "DNS lookup failed"
