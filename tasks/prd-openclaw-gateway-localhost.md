# PRD: OpenClaw Gateway Localhost Access via Virtio-Vsock

## Introduction

The openclaw-gateway enforces a security policy: it only accepts connections via HTTPS or localhost. Currently, connections from the host are proxied via TCP through the TAP bridge, causing the gateway to see connections from `10.88.0.1` (host bridge IP) rather than `127.0.0.1`. This triggers the gateway's security rejection.

This PRD addresses making the gateway accessible from the host while respecting its security constraints, using virtio-vsock to present connections as localhost to the guest.

## Goals

- Enable localhost CLI access to the gateway from the host machine
- Enable HTTPS browser access via Caddy on the host
- Maintain the gateway's security model (HTTPS or localhost only)
- No changes required to the openclaw-gateway binary itself
- Clean integration with existing NixOS/microvm infrastructure

## User Stories

### US-001: Configure virtio-vsock for host-guest communication
**Description:** As a host system, I need a virtio-vsock channel to the VM so that connections appear as localhost to guest services.

**Acceptance Criteria:**
- [ ] QEMU configured with `-device vhost-vsock-pci,guest-cid=<CID>`
- [ ] Guest kernel has vsock support enabled
- [ ] vsock device appears in guest as `/dev/vsock`
- [ ] Host can connect via `/dev/vhost-vsock` or `AF_VSOCK` socket
- [ ] Typecheck/eval passes: `nix flake check --no-build 2>&1`

### US-002: Gateway binds to localhost inside VM
**Description:** As the gateway service, I should bind only to localhost since all legitimate connections will come via vsock (which presents as localhost).

**Acceptance Criteria:**
- [ ] Gateway `ExecStart` uses `--bind localhost` instead of `--bind lan`
- [ ] Gateway only listens on `127.0.0.1:18789` inside VM
- [ ] Firewall rules updated (no need to allow external port)
- [ ] Typecheck/eval passes

### US-003: Guest-side vsock-to-localhost proxy
**Description:** As the VM, I need a service that accepts vsock connections and forwards them to the gateway's localhost port.

**Acceptance Criteria:**
- [ ] systemd service runs socat or similar: `VSOCK-LISTEN:<port> -> TCP:127.0.0.1:18789`
- [ ] Service starts before gateway is expected to receive connections
- [ ] Service restarts on failure
- [ ] Typecheck/eval passes

### US-004: Host-side localhost-to-vsock proxy
**Description:** As a CLI user on the host, I want to connect to `localhost:18789` and have it reach the gateway.

**Acceptance Criteria:**
- [ ] systemd service runs socat: `TCP-LISTEN:18789,bind=127.0.0.1 -> VSOCK:<CID>:<port>`
- [ ] Replaces existing `openclaw-gateway-proxy` socat service
- [ ] Service starts after VM is running
- [ ] Connections to `localhost:18789` on host reach gateway
- [ ] Typecheck/eval passes

### US-005: Caddy HTTPS reverse proxy on host
**Description:** As a browser user, I want HTTPS access to the gateway for secure web-based interaction.

**Acceptance Criteria:**
- [ ] Caddy enabled and configured for `localhost:8443` HTTPS
- [ ] Uses internal CA (user can run `caddy trust` for browser trust)
- [ ] Reverse proxies to `localhost:18789` (the vsock proxy)
- [ ] WebSocket headers properly forwarded
- [ ] Typecheck/eval passes

### US-006: Remove TAP-based gateway access
**Description:** As the system, I should not expose the gateway over the TAP network since vsock handles all gateway traffic.

**Acceptance Criteria:**
- [ ] Guest firewall no longer opens gateway port to TAP interface
- [ ] No DNAT or port forwarding rules for gateway port
- [ ] TAP network remains for outbound internet access from VM
- [ ] Typecheck/eval passes

## Functional Requirements

- FR-1: Add virtio-vsock device to QEMU configuration with a stable CID (e.g., 3)
- FR-2: Change gateway binding from `--bind lan` to `--bind localhost`
- FR-3: Create guest systemd service `vsock-gateway-proxy` that forwards vsock port 18789 to localhost:18789
- FR-4: Modify host `openclaw-gateway-proxy` to use vsock instead of TCP to VM IP
- FR-5: Enable Caddy HTTPS on port 8443 with internal CA, proxying to localhost:18789
- FR-6: Remove gateway port from guest firewall allowedTCPPorts
- FR-7: Ensure vsock kernel module loads in guest (virtio_vsock)

## Non-Goals

- No modifications to the openclaw-gateway binary
- No external network exposure of the gateway (localhost/vsock only)
- No mTLS or client certificate authentication (token auth via config is sufficient)
- No zero-trust infrastructure integration (sops-only for this PRD)
- No changes to TAP networking for other services (only gateway moves to vsock)

## Technical Considerations

### Virtio-Vsock Architecture
```
Host                          │  Guest VM
                              │
localhost:18789 ──┐           │
                  │           │
Browser ─► Caddy:8443 ────────┼──► vsock-gateway-proxy ──► Gateway:127.0.0.1:18789
     (HTTPS)      │           │      (VSOCK-LISTEN)           (localhost only)
                  │           │
CLI ──► socat ────┘           │
    (localhost:18789          │
     → VSOCK:3:18789)         │
```

### QEMU vsock Configuration
- Device: `vhost-vsock-pci`
- Guest CID: 3 (1=host, 2=reserved, 3+=guests)
- Host connects to CID 3, port 18789

### Kernel Requirements
- Host: `vhost_vsock` module
- Guest: `virtio_vsock` module (usually built into microvm kernels)

### socat vsock syntax
- Guest: `socat VSOCK-LISTEN:18789,fork TCP:127.0.0.1:18789`
- Host: `socat TCP-LISTEN:18789,bind=127.0.0.1,fork VSOCK-CONNECT:3:18789`

## Success Metrics

- `curl http://localhost:18789/health` from host returns success
- `curl https://localhost:8443/health` from host returns success (after `caddy trust`)
- Gateway logs show connections from `127.0.0.1`, not `10.88.0.1`
- No security rejection messages from gateway

## Open Questions

1. Does the microvm.nix module have built-in vsock support, or do we need raw QEMU args?
2. What vsock port should we use? (Using 18789 to match gateway port for simplicity)
3. Should we add a health check that verifies the full vsock chain is working?
4. Is socat the best tool, or should we use a dedicated vsock proxy (e.g., `virtio-vsock-proxy`)?
