#!/usr/bin/env bash
set -euo pipefail

echo "=== OpenClaw Gateway Verification ==="
echo

# Check systemd service status
echo "1. Checking systemd service status..."
if systemctl --user is-active --quiet openclaw-gateway 2>/dev/null; then
    echo "   [OK] openclaw-gateway is running"
    systemctl --user status openclaw-gateway --no-pager | head -10
else
    echo "   [--] openclaw-gateway is not running"
    echo "   Starting service..."
    systemctl --user start openclaw-gateway
    sleep 2
    if systemctl --user is-active --quiet openclaw-gateway; then
        echo "   [OK] Started successfully"
    else
        echo "   [FAIL] Failed to start"
        journalctl --user -u openclaw-gateway --no-pager -n 20
        exit 1
    fi
fi
echo

# Check if port is listening
PORT=18789
echo "2. Checking if port $PORT is listening..."
if ss -tlnp 2>/dev/null | grep -q ":$PORT"; then
    echo "   [OK] Port $PORT is listening"
    ss -tlnp | grep ":$PORT"
else
    echo "   [FAIL] Port $PORT is not listening"
    exit 1
fi
echo

# Try to reach the gateway
echo "3. Checking HTTP response..."
if curl -sI --max-time 5 "http://127.0.0.1:$PORT" >/dev/null 2>&1; then
    echo "   [OK] Gateway is responding"
    curl -sI --max-time 5 "http://127.0.0.1:$PORT" | head -5
else
    echo "   [--] No HTTP response (may be WebSocket-only)"
fi
echo

echo "=== Verification Complete ==="
echo "Gateway URL: http://localhost:$PORT"
