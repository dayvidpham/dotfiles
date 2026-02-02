#!/usr/bin/env bash
# Comprehensive network diagnostics for openclaw-vm
# Run on HOST as root: sudo ./debug-vm-network.sh
#
# Covers: bridge, TAP, routing, forwarding, NAT, nftables, iptables, rpfilter, DNS

set -euo pipefail

# Configuration
VM_IP="10.88.0.2"
VM_NET="10.88.0.0/24"
BRIDGE="br-openclaw"
TAP="vm-openclaw"
GATEWAY_PORT="18789"
VSOCK_CID="4"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "   ${GREEN}✓${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; }
warn() { echo -e "   ${YELLOW}!${NC} $1"; }
info() { echo -e "   $1"; }

OUTPUT_DIR="/tmp/vm-network-debug-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "=== OpenClaw VM Network Diagnostics ==="
echo "Output directory: $OUTPUT_DIR"
echo ""

#################################################
echo "1. INTERFACE CHECKS"
#################################################

# Bridge exists
if ip link show "$BRIDGE" &>/dev/null; then
    pass "Bridge $BRIDGE exists"
    ip addr show "$BRIDGE" > "$OUTPUT_DIR/bridge.txt"

    # Bridge has IP
    if ip -4 addr show "$BRIDGE" | grep -q "inet "; then
        BRIDGE_IP=$(ip -4 addr show "$BRIDGE" | grep -oP 'inet \K[\d./]+')
        pass "Bridge has IP: $BRIDGE_IP"
    else
        fail "Bridge has no IPv4 address"
    fi

    # Bridge is UP
    if ip link show "$BRIDGE" | grep -q "state UP"; then
        pass "Bridge is UP"
    else
        fail "Bridge is DOWN"
    fi
else
    fail "Bridge $BRIDGE not found"
fi

# TAP interface
if ip link show "$TAP" &>/dev/null; then
    pass "TAP interface $TAP exists"
    ip addr show "$TAP" > "$OUTPUT_DIR/tap.txt"

    # TAP attached to bridge
    if bridge link show | grep -q "$TAP.*master $BRIDGE"; then
        pass "TAP attached to bridge"
    else
        fail "TAP not attached to bridge"
    fi

    # TAP is UP
    if ip link show "$TAP" | grep -q "state UP"; then
        pass "TAP is UP"
    else
        fail "TAP is DOWN"
    fi
else
    fail "TAP interface $TAP not found"
fi

echo ""

#################################################
echo "2. VM CONNECTIVITY"
#################################################

# Ping VM
if ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
    pass "Host can ping VM ($VM_IP)"
else
    fail "Host cannot ping VM ($VM_IP)"
fi

# ARP entry
if ip neigh show | grep -q "$VM_IP"; then
    MAC=$(ip neigh show | grep "$VM_IP" | awk '{print $5}')
    pass "ARP entry exists for VM: $MAC"
else
    warn "No ARP entry for VM (may be normal if no recent traffic)"
fi

# VSOCK
if [[ -c /dev/vhost-vsock ]]; then
    pass "VSOCK device exists"
else
    fail "VSOCK device /dev/vhost-vsock missing"
fi

echo ""

#################################################
echo "3. KERNEL SETTINGS"
#################################################

# IP forwarding
FWD=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ "$FWD" == "1" ]]; then
    pass "IPv4 forwarding enabled"
else
    fail "IPv4 forwarding disabled"
fi

FWD6=$(cat /proc/sys/net/ipv6/conf/all/forwarding)
if [[ "$FWD6" == "1" ]]; then
    pass "IPv6 forwarding enabled"
else
    info "IPv6 forwarding disabled (may be intentional)"
fi

# Reverse path filtering
RP_FILTER=$(cat /proc/sys/net/ipv4/conf/all/rp_filter)
RP_BRIDGE=$(cat /proc/sys/net/ipv4/conf/$BRIDGE/rp_filter 2>/dev/null || echo "N/A")
info "rp_filter: all=$RP_FILTER, $BRIDGE=$RP_BRIDGE"

echo ""

#################################################
echo "4. ROUTING"
#################################################

ip route > "$OUTPUT_DIR/routes.txt"

# Route to VM
if ip route get "$VM_IP" &>/dev/null; then
    ROUTE=$(ip route get "$VM_IP")
    pass "Route to VM exists"
    info "  $ROUTE"
else
    fail "No route to VM"
fi

# Default route
if ip route | grep -q "^default"; then
    DEFAULT=$(ip route | grep "^default" | head -1)
    pass "Default route exists"
    info "  $DEFAULT"
else
    fail "No default route"
fi

echo ""

#################################################
echo "5. NFTABLES RULES"
#################################################

nft list ruleset > "$OUTPUT_DIR/nftables-full.txt"

# List all tables
echo "   Tables:"
nft list tables | while read -r table; do
    info "    $table"
done

# openclaw-vm-firewall
if nft list table inet openclaw-vm-firewall &>/dev/null; then
    pass "openclaw-vm-firewall table exists"
    nft list table inet openclaw-vm-firewall > "$OUTPUT_DIR/nft-openclaw.txt"

    # Check masquerade
    if grep -q masquerade "$OUTPUT_DIR/nft-openclaw.txt"; then
        pass "Masquerade rule exists"
    else
        fail "Masquerade rule missing"
    fi

    # Check forward chain priority
    PRIORITY=$(grep -oP 'priority \K[-\d]+' "$OUTPUT_DIR/nft-openclaw.txt" | head -1 || echo "unknown")
    info "Forward chain priority: $PRIORITY"
    if [[ "$PRIORITY" == "0" ]] || [[ "$PRIORITY" == "filter" ]]; then
        warn "Priority 0 may conflict with iptables-nft, recommend -10"
    fi

    # Check forward counters
    if grep -q "counter packets 0" "$OUTPUT_DIR/nft-openclaw.txt"; then
        warn "Forward chain counters are zero (no traffic matched)"
    fi
else
    fail "openclaw-vm-firewall table missing"
fi

# nixos-fw rpfilter
if nft list chain inet nixos-fw rpfilter &>/dev/null; then
    nft list chain inet nixos-fw rpfilter > "$OUTPUT_DIR/nft-rpfilter.txt"

    # Also check rpfilter-allow (where NixOS adds exceptions via jump)
    if nft list chain inet nixos-fw rpfilter-allow &>/dev/null; then
        nft list chain inet nixos-fw rpfilter-allow >> "$OUTPUT_DIR/nft-rpfilter.txt"
    fi

    if grep -q "$VM_NET\|10.88.0" "$OUTPUT_DIR/nft-rpfilter.txt"; then
        pass "rpfilter has VM network exception"
    else
        fail "rpfilter missing VM network exception"
        warn "Fix: nft insert rule inet nixos-fw rpfilter-allow ip saddr $VM_NET accept"
    fi
else
    info "nixos-fw rpfilter chain not found (may be okay)"
fi

echo ""

#################################################
echo "6. IPTABLES-NFT (legacy compatibility)"
#################################################

# Check if iptables tables exist
if nft list table ip filter &>/dev/null; then
    warn "iptables-nft 'ip filter' table exists (potential conflict)"
    nft list table ip filter > "$OUTPUT_DIR/iptables-filter.txt"

    # Check FORWARD policy
    POLICY=$(grep -oP 'policy \K\w+' "$OUTPUT_DIR/iptables-filter.txt" | tail -1 || echo "unknown")
    info "iptables FORWARD policy: $POLICY"

    # Check for tailscale rules
    if grep -q ts-forward "$OUTPUT_DIR/iptables-filter.txt"; then
        info "Tailscale rules present in iptables"
    fi
else
    pass "No iptables-nft filter table (good)"
fi

if nft list table ip nat &>/dev/null; then
    nft list table ip nat > "$OUTPUT_DIR/iptables-nat.txt"
    info "iptables-nft NAT table exists"
else
    pass "No iptables-nft NAT table"
fi

echo ""

#################################################
echo "7. DNS CONFIGURATION"
#################################################

# systemd-resolved status
if systemctl is-active systemd-resolved &>/dev/null; then
    pass "systemd-resolved is running"
    resolvectl status > "$OUTPUT_DIR/resolved.txt" 2>&1 || true

    # Check if listening on bridge IP
    BRIDGE_LISTEN_IP=$(echo "$BRIDGE_IP" | cut -d'/' -f1)
    if ss -ulnp | grep -q "$BRIDGE_LISTEN_IP:53"; then
        pass "resolved listening on bridge IP ($BRIDGE_LISTEN_IP:53)"
    else
        warn "resolved not listening on bridge IP"
        info "Check: ss -ulnp | grep :53"
    fi
else
    warn "systemd-resolved not running"
fi

echo ""

#################################################
echo "8. FIREWALL INPUT RULES (for DNS)"
#################################################

if nft list chain inet nixos-fw input-allow &>/dev/null; then
    nft list chain inet nixos-fw input-allow > "$OUTPUT_DIR/nft-input-allow.txt"

    if grep -q "dport 53" "$OUTPUT_DIR/nft-input-allow.txt"; then
        pass "DNS port 53 allowed in firewall"
    else
        fail "DNS port 53 not in firewall input-allow"
    fi
else
    warn "nixos-fw input-allow chain not found"
fi

echo ""

#################################################
echo "9. SERVICES STATUS"
#################################################

for svc in "microvm@openclaw-vm" "openclaw-gateway-proxy"; do
    if systemctl is-active "$svc" &>/dev/null; then
        pass "$svc is running"
    else
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "unknown")
        fail "$svc is $STATUS"
    fi
    systemctl status "$svc" --no-pager > "$OUTPUT_DIR/svc-${svc//[@\/]/-}.txt" 2>&1 || true
done

echo ""

#################################################
echo "10. LIVE TRAFFIC TEST"
#################################################

echo "   Adding debug counters..."

# Add counters if not present
nft add rule inet openclaw-vm-firewall forward counter 2>/dev/null || true

echo "   Capturing traffic for 5 seconds (try curl from VM now)..."
timeout 5 tcpdump -i "$BRIDGE" -c 20 -n 'icmp or tcp port 80 or tcp port 443' > "$OUTPUT_DIR/tcpdump.txt" 2>&1 &
TCPDUMP_PID=$!

sleep 5
kill $TCPDUMP_PID 2>/dev/null || true

PACKETS=$(wc -l < "$OUTPUT_DIR/tcpdump.txt" || echo 0)
if [[ "$PACKETS" -gt 0 ]]; then
    pass "Captured $PACKETS packets on bridge"
    head -10 "$OUTPUT_DIR/tcpdump.txt" | while read -r line; do
        info "  $line"
    done
else
    warn "No matching traffic captured"
fi

echo ""

#################################################
echo "=== SUMMARY ==="
#################################################

echo ""
echo "Diagnostic files saved to: $OUTPUT_DIR"
echo ""
echo "Common fixes:"
echo ""
echo "1. rpfilter blocking VM traffic:"
echo "   nft insert rule inet nixos-fw rpfilter ip saddr $VM_NET counter accept"
echo ""
echo "2. nftables priority conflict with iptables-nft:"
echo "   Change forward chain from 'priority filter' to 'priority -10'"
echo ""
echo "3. Test VM connectivity manually:"
echo "   # From VM:"
echo "   curl -4 --connect-timeout 5 http://1.1.1.1"
echo "   host hs0.vpn.dhpham.com"
echo ""
echo "4. Check rpfilter drops:"
echo "   journalctl -k | grep 'rpfilter drop' | tail -20"
echo ""
echo "5. Watch nftables counters:"
echo "   watch -n1 'nft list chain inet openclaw-vm-firewall forward'"
