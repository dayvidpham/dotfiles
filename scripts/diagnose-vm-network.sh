#!/usr/bin/env bash
# Diagnostic script for openclaw-vm networking issues
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== OpenClaw VM Network Diagnostics ==="
echo ""

# 1. Check if VM is running
echo "--- 1. VM Service Status ---"
if systemctl is-active --quiet microvm@openclaw-vm; then
    echo -e "${GREEN}✓ microvm@openclaw-vm is running${NC}"
else
    echo -e "${RED}✗ microvm@openclaw-vm is NOT running${NC}"
    systemctl status microvm@openclaw-vm --no-pager 2>&1 | head -20 || true
fi
echo ""

# 2. Check sysctl settings
echo "--- 2. Kernel Sysctl Settings ---"
IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "UNAVAILABLE")
ROUTE_LOCALNET=$(sysctl -n net.ipv4.conf.lo.route_localnet 2>/dev/null || echo "UNAVAILABLE")

if [[ "$IP_FORWARD" == "1" ]]; then
    echo -e "${GREEN}✓ net.ipv4.ip_forward = 1${NC}"
else
    echo -e "${RED}✗ net.ipv4.ip_forward = $IP_FORWARD (should be 1)${NC}"
fi

if [[ "$ROUTE_LOCALNET" == "1" ]]; then
    echo -e "${GREEN}✓ net.ipv4.conf.lo.route_localnet = 1${NC}"
else
    echo -e "${RED}✗ net.ipv4.conf.lo.route_localnet = $ROUTE_LOCALNET (should be 1)${NC}"
    echo -e "${YELLOW}  This is required for DNAT from localhost to work!${NC}"
fi
echo ""

# 3. Check bridge interface
echo "--- 3. Bridge Interface (br-openclaw) ---"
if ip link show br-openclaw &>/dev/null; then
    echo -e "${GREEN}✓ br-openclaw exists${NC}"
    ip addr show br-openclaw | grep -E '(state|inet )' | sed 's/^/  /'
else
    echo -e "${RED}✗ br-openclaw does NOT exist${NC}"
fi
echo ""

# 4. Check TAP interface
echo "--- 4. TAP Interface (vm-openclaw) ---"
if ip link show vm-openclaw &>/dev/null; then
    echo -e "${GREEN}✓ vm-openclaw exists${NC}"
    ip addr show vm-openclaw | grep -E '(state|master)' | sed 's/^/  /'
else
    echo -e "${RED}✗ vm-openclaw does NOT exist${NC}"
fi
echo ""

# 5. Check nftables rules
echo "--- 5. nftables Rules ---"
if sudo nft list table inet openclaw-vm-firewall &>/dev/null; then
    echo -e "${GREEN}✓ openclaw-vm-firewall table exists${NC}"
    echo "  DNAT rule:"
    sudo nft list table inet openclaw-vm-firewall 2>/dev/null | grep -E '(dnat|18789)' | sed 's/^/    /' || echo "    (no DNAT rules found)"
else
    echo -e "${RED}✗ openclaw-vm-firewall table does NOT exist${NC}"
fi
echo ""

# 6. Ping test to VM
echo "--- 6. Ping Test to VM (10.88.0.2) ---"
if ping -c 1 -W 2 10.88.0.2 &>/dev/null; then
    echo -e "${GREEN}✓ VM is reachable at 10.88.0.2${NC}"
else
    echo -e "${RED}✗ Cannot ping VM at 10.88.0.2${NC}"
fi
echo ""

# 7. Direct connection test to VM
echo "--- 7. Direct Connection Test (10.88.0.2:18789) ---"
if curl -s --connect-timeout 3 http://10.88.0.2:18789/health &>/dev/null; then
    echo -e "${GREEN}✓ Direct connection to 10.88.0.2:18789 works${NC}"
    curl -s http://10.88.0.2:18789/health | head -c 200
    echo ""
elif timeout 3 bash -c 'cat < /dev/null > /dev/tcp/10.88.0.2/18789' 2>/dev/null; then
    echo -e "${YELLOW}~ Port 18789 is open but /health endpoint not responding${NC}"
else
    echo -e "${RED}✗ Cannot connect to 10.88.0.2:18789${NC}"
fi
echo ""

# 8. DNAT test via localhost
echo "--- 8. DNAT Test (localhost:18789) ---"
if curl -s --connect-timeout 3 http://localhost:18789/health &>/dev/null; then
    echo -e "${GREEN}✓ DNAT via localhost:18789 works${NC}"
    curl -s http://localhost:18789/health | head -c 200
    echo ""
elif timeout 3 bash -c 'cat < /dev/null > /dev/tcp/127.0.0.1/18789' 2>/dev/null; then
    echo -e "${YELLOW}~ Port 18789 is reachable but /health endpoint not responding${NC}"
else
    echo -e "${RED}✗ Cannot connect via localhost:18789${NC}"
fi
echo ""

# 9. Check if anything is listening on 18789 on host
echo "--- 9. Host Port 18789 Listeners ---"
HOST_LISTENERS=$(ss -tlnp 2>/dev/null | grep ':18789' || true)
if [[ -n "$HOST_LISTENERS" ]]; then
    echo -e "${YELLOW}! Something is listening on port 18789 on host (may conflict with DNAT):${NC}"
    echo "$HOST_LISTENERS" | sed 's/^/  /'
else
    echo -e "${GREEN}✓ No host process listening on 18789 (good for DNAT)${NC}"
fi
echo ""

# 10. Check systemd-resolved DNS listener
echo "--- 10. DNS Stub Listener on Bridge ---"
if ss -ulnp 2>/dev/null | grep -q '10.88.0.1:53'; then
    echo -e "${GREEN}✓ systemd-resolved listening on 10.88.0.1:53${NC}"
else
    echo -e "${YELLOW}~ systemd-resolved may not be listening on bridge IP${NC}"
fi
echo ""

# Summary
echo "=== Summary ==="
ISSUES=0

[[ "$IP_FORWARD" != "1" ]] && ((ISSUES++)) && echo -e "${RED}• Enable ip_forward: sudo sysctl -w net.ipv4.ip_forward=1${NC}"
[[ "$ROUTE_LOCALNET" != "1" ]] && ((ISSUES++)) && echo -e "${RED}• Enable route_localnet: sudo sysctl -w net.ipv4.conf.lo.route_localnet=1${NC}"
! ip link show br-openclaw &>/dev/null && ((ISSUES++)) && echo -e "${RED}• Bridge missing - check systemd-networkd${NC}"
! ip link show vm-openclaw &>/dev/null && ((ISSUES++)) && echo -e "${RED}• TAP missing - VM may not be running${NC}"
! ping -c 1 -W 1 10.88.0.2 &>/dev/null && ((ISSUES++)) && echo -e "${RED}• VM unreachable - check guest network config${NC}"

if [[ $ISSUES -eq 0 ]]; then
    echo -e "${GREEN}No obvious issues detected. Check VM console for gateway service status.${NC}"
else
    echo -e "${YELLOW}Found $ISSUES potential issue(s) above.${NC}"
fi

echo ""
echo "To check inside VM: openclaw-vm-console"
echo "Then run: ip addr show enp0s4 && systemctl status openclaw-gateway"
