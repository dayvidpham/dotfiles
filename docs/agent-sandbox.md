---
description: Implementation plan for secure agentic sandbox with credential proxy
created: 2026-02-05
date: 2026-02-05
---

# Implementation Plan: Secure Agentic Sandbox with Credential Proxy

## Overview

This plan implements a **network-isolated agent architecture** where:
- Agent runs in gVisor sandbox with **zero external network access**
- All network calls delegated to **ACP-compliant proxy service**
- Credentials stored in **OpenBao** with **domain binding**
- Responses use **templated format** for scripting flexibility

## User Request (verbatim)

> I want to find an open-source project that focuses on secure agentic sandboxes, whether as an OCI container or as a VM. The main attack vector is defending against prompt injection and API key leakage into the agent transcripts, caused by the agent inside the sandbox, which may be Claude Code with --dangerously-skip-permissions running autonomously, as a non-root user.

## User Requirements (verbatim)

- **Credential Lookup**: Should support both explicit credential reference (`openclaw/api/key`) and target domain/path binding
- **Domain Binding**: Credentials should be bound to specific domains (e.g., `openclaw/api/key` only works for `api.openclaw.com`)
- **Templated Responses**: Responses should use templated format for scripting flexibility (e.g., `{ "name": {{sensitive_name}} }`)
- **ACP Subset**: Implement a subset of ACP (Agent-Client Protocol) - just what's needed to implement the service

## User Questions and Agent Answers

### Q: Should credentials be bound to specific domains?
**A**: Yes, should be bound to specific domains.

### Q: How should templated responses handle PII?
**A**: Responses will use templated format. PII handling depends on application-level, which we can provide an SDK on top of.

### Q: ACP Implementation approach?
**A**: Implement a subset of ACP - just what we need to implement the service.

### Q: What about database connections and other non-HTTP protocols?
**A**: Mostly HTTPS for now. The "proxy" means the agent's environment has no externally-connected network to begin with - it must delegate all network calls to the outer sandbox.

### Q: How does credential lookup work?
**A**: Both explicit credential reference and target domain/path binding.

## User Design Decisions

1. **Network Isolation**: Agent runs in gVisor sandbox with `network=none`
2. **Credential Storage**: OpenBao with domain-bound credentials
3. **Communication Protocol**: ACP subset for agent-proxy communication
4. **Response Format**: Templated JSON for scripting flexibility
5. **Proxy Location**: Trusted service outside sandbox
6. **Audit Trail**: Comprehensive logging of all credential access

## User Motivations and Desired Tradeoffs

- **Primary Goal**: Prevent API key leakage into agent transcripts
- **Threat Model**: Defend against compromised agent with `--dangerously-skip-permissions`
- **Balance**: Strong security vs. usability for autonomous agents
- **Flexibility**: Templated responses enable scripting while protecting PII
- **Scalability**: Domain-bound credentials prevent credential misuse

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Host (NixOS)                                                                 │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Inner Sandbox (gVisor)                                               │    │
│  │  ┌───────────────────────────────────────────────────────────────┐  │    │
│  │  │ Claude Code (--dangerously-skip-permissions)                   │  │    │
│  │  │                                                               │  │    │
│  │  │ No network! All requests via ACP → /run/proxy.sock          │  │    │
│  │  │                                                               │  │    │
│  │  │ Response format: templated for scripting                    │  │    │
│  │  │   { "status": {{status}}, "data": {{data}} }                 │  │    │
│  │  └───────────────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                    ▲                                                      │
│                    │ Unix socket (agent-only-write)                       │
│                    │                                                      │
│  ┌─────────────────┴─────────────────────────────────────────────────────┐  │
│  │ Proxy Service (trusted)                                             │  │
│  │  ┌───────────────────────────────────────────────────────────────┐  │  │
│  │  │ ACP Subset Implementation                                      │  │  │
│  │  │                                                               │  │  │
│  │  │ 1. Validate ACP request                                        │  │  │
│  │  │ 2. Lookup credentials (ref + domain mapping)                 │  │  │
│  │  │ 3. Verify domain binding (credential.domain == request.domain)│  │  │
│  │  │ 4. Inject auth headers / sign request                         │  │  │
│  │  │ 5. Forward to external API (HTTPS only)                       │  │  │
│  │  │ 6. Template response → agent format                          │  │  │
│  │  │ 7. Audit log everything                                       │  │  │
│  │  │                                                               │  │  │
│  │  │ Security Controls:                                            │  │  │
│  │  │ - Rate limiting per agent                                     │  │  │
│  │  │ - Request size limits                                         │  │  │
│  │  │ - Response size limits                                        │  │  │
│  │  └───────────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                    │                                                      │
│                    │ mTLS + API token (proxy → OpenBao)                  │
│                    ▼                                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ OpenBao (Vault)                                                     │  │
│  │  ┌───────────────────────────────────────────────────────────────┐  │  │
│  │  │ Credentials Store                                              │  │  │
│  │  │   - openclaw/api/key: { key, domain: "api.openclaw.com" }    │  │  │
│  │  │   - db/creds: { user, pass, domain: "db.internal" }          │  │  │
│  │  │                                                               │  │  │
│  │  │ Policy Engine                                                  │  │  │
│  │  │   - Domain binding enforcement                               │  │  │
│  │  │   - Rate limits                                               │  │  │
│  │  │   - IP allowlisting                                           │  │  │
│  │  │                                                               │  │  │
│  │  │ Audit Log                                                     │  │  │
│  │  │   - Who (agent_id), What (credential), When, Result         │  │  │
│  │  └───────────────────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │ External Network (HTTPS only)                                       │  │
│  │   - Proxy makes all outbound calls                                 │  │
│  │   - Agent never touches network                                    │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## ACP Subset Specification

### Request Format (Agent → Proxy)

```json
{
  "acp_version": "1.0",
  "request_id": "req_abc123",
  "agent_id": "agent_001",
  "timestamp": "2024-01-15T10:30:00Z",
  "credential": {
    "ref": "openclaw/api/key",
    "domain": "api.openclaw.com"
  },
  "target": {
    "method": "POST",
    "path": "/api/v2/data",
    "headers": {
      "Content-Type": "application/json"
    },
    "body_base64": "eyJrZXkiOiJ2YWx1ZSJ9"
  },
  "response_template": {
    "format": "json",
    "fields": ["status", "data.id", "data.name"]
  }
}
```

### Response Format (Proxy → Agent)

```json
{
  "acp_version": "1.0",
  "request_id": "req_abc123",
  "status": "success",
  "response": {
    "status": {{response.status}},
    "data.id": {{response.data.id}},
    "data.name": {{response.data.name}}
  },
  "metadata": {
    "processed_at": "2024-01-15T10:30:01Z",
    "response_size_bytes": 1024
  }
}
```

## Implementation Phases

### Phase 1: OpenBao Setup
- [ ] Deploy OpenBao (standalone mode for simplicity)
- [ ] Configure TLS certificates
- [ ] Create policies:
  - `proxy-policy`: Read access to all credentials
  - `agent-policy`: Audit-only (no direct secret access)
- [ ] Seed credentials with domain bindings:
  ```bash
  openbao secrets enable -path=openclaw kv
  openbao kv put openclaw/api/key key="sk-xxx" domain="api.openclaw.com"
  openbao kv put db/creds user="app" pass="yyy" domain="db.internal"
  ```

### Phase 2: Proxy Service
- [ ] Create Rust/Go service (choose language)
- [ ] Implement ACP subset parser
- [ ] Implement OpenBao client
- [ ] Implement domain binding verification
- [ ] Implement templating engine
- [ ] Add audit logging
- [ ] Add rate limiting
- [ ] Expose Unix socket with restricted permissions

### Phase 3: gVisor Sandbox Configuration
- [ ] Configure gVisor with `--directfs=true`
- [ ] Disable networking:
  ```bash
  runsc run \
    --network=none \
    --volume=/run/proxy.sock:/run/proxy.sock:rwx \
    --socket-uid=0 \
    --socket-gid=1000 \
    agent-sandbox
  ```
- [ ] Set socket permissions (agent can write, cannot read)

### Phase 4: Agent Integration
- [ ] Create ACP client SDK for Claude Code
- [ ] Implement request construction
- [ ] Implement response parsing with template substitution
- [ ] Test end-to-end flow

### Phase 5: Security Hardening
- [ ] Add mTLS between proxy and OpenBao
- [ ] Implement request/response size limits
- [ ] Add circuit breaker for OpenBao failures
- [ ] Implement audit dashboard

## Credential Binding Enforcement Logic

```python
def validate_credential_binding(credential_ref: str, domain: str, openbao_client) -> bool:
    """
    Ensures credential can only be used for its bound domain.
    """
    secret = openbao_client.read(credential_ref)
    
    bound_domain = secret.get("domain")
    if bound_domain and bound_domain != domain:
        raise CredentialDomainMismatch(
            f"Credential {credential_ref} is bound to {bound_domain}, "
            f"cannot use for {domain}"
        )
    
    return True
```

## Templated Response Example

**Raw API Response:**
```json
{
  "status": "success",
  "data": {
    "id": "12345",
    "name": "John Doe",
    "ssn": "123-45-6789",
    "credit_card": "4111-1111-1111-1111"
  }
}
```

**Agent Request Template:**
```json
{
  "response_template": {
    "format": "json",
    "fields": ["status", "data.id", "data.name"]
  }
}
```

**Agent Receives:**
```json
{
  "status": "success",
  "data": {
    "id": "12345",
    "name": "John Doe"
  }
}
```

## Security Properties

| Threat | Mitigation |
|--------|------------|
| Agent leaks API key in transcript | Agent never sees keys - proxy handles auth |
| Agent exfiltrates credential | Domain binding prevents use on other domains |
| Compromised agent spams proxy | Rate limiting per agent_id |
| Proxy compromised | Separate VM, mTLS to OpenBao, audit logging |
| OpenBao compromised | Network isolation, IP allowlisting |
| gVisor escape | Agent still needs auth to reach proxy |

## Files to Create

| File | Purpose |
|------|---------|
| `proxy/src/main.rs` | Proxy service entry point |
| `proxy/src/acp.rs` | ACP protocol implementation |
| `proxy/src/openbao.rs` | OpenBao client wrapper |
| `proxy/src/templates.rs` | Response templating engine |
| `proxy/src/audit.rs` | Audit logging |
| `sandbox/gvisor.nix` | gVisor configuration for NixOS |
| `sandbox/proxy.socket` | Systemd socket unit |
| `sandbox/proxy.service` | Systemd service unit |

---

## Addendum: Existing Implementation Assessment (2026-02-05)

Research was conducted to identify existing open-source projects with similar goals. The following table summarizes findings:

| Project | Stars | Isolation | Credential Proxy | Domain Binding | Self-Hosted |
|---------|-------|-----------|------------------|----------------|-------------|
| **anthropic-experimental/sandbox-runtime** | 2.9k | Bubblewrap | ❌ No | Partial (filtering) | ✅ Yes |
| **abshkbh/arrakis** | 753 | MicroVM | ❌ No | ❌ No | ✅ Yes |
| **Agent Sandbox** (K8s) | — | gVisor/Kata | ❌ No | ❌ No | Partial |
| **API Stronghold** | — | VM/Container | ✅ Yes | ✅ Yes | ✅ Yes |

### Key Finding

**anthropic-experimental/sandbox-runtime** is the closest existing implementation but **missing the core credential proxy functionality**:

| Capability | sandbox-runtime | This Plan |
|------------|-----------------|-----------|
| Network isolation via proxy | ✅ Yes | ✅ Yes |
| Unix socket routing pattern | ✅ Yes | ✅ Yes |
| Domain allowlist filtering | ✅ Yes | ✅ Yes |
| **Credential injection** | ❌ No | ✅ Yes |
| **Vault/OpenBao integration** | ❌ No | ✅ Yes |
| **Templated responses** | ❌ No | ✅ Yes |
| **Audit logging** | ❌ No | ✅ Yes |

The `sandbox-runtime` project routes traffic through host proxies but agents must still have credentials in their environment—this does not prevent API key leakage.

### Feasibility Summary

| Component | Complexity | Reuse Existing? |
|-----------|------------|-----------------|
| OpenBao Setup | Low | ✅ Yes |
| Proxy Service | Medium | ⚠️ Partial |
| ACP Subset | Low | ⚠️ Partial |
| gVisor Sandbox | Medium | ✅ Yes |
| Domain Binding | Low | ⚠️ Custom |
| Templated Responses | Low | ⚠️ Custom |
| Audit Logging | Low | ⚠️ Custom |

### Recommendation

The plan is **feasible** with the following guidance:

1. **Reuse `anthropic-experimental/sandbox-runtime`** for network isolation foundation instead of building bubblewrap integration from scratch
2. **Build the credential proxy layer** on top—this is the novel component not covered by existing projects
3. **No major components have been completed**—this remains a custom implementation
4. **No conflicting prior work** exists in the codebase

---

## Addendum: Alternative Existing Implementations (2026-02-05)

Two additional projects were identified that are **directly relevant** to this plan:

### Vultrino — Credential Proxy for AI Era

| Attribute | Value |
|-----------|-------|
| Stars | 5 |
| License | MIT |
| Language | Rust (82.2%) |
| Self-Hosted | ✅ Yes |

**Key Features:**
- ✅ **Credential isolation** — agents never see API keys
- ✅ **MCP integration** — native Model Context Protocol server
- ✅ **Encrypted storage** — AES-256-GCM with Argon2 key derivation
- ✅ **Policy engine** — URL patterns, method restrictions, rate limiting
- ✅ **Audit logging** — track all credential usage
- ✅ **Role-based access control** — scoped API keys
- ✅ **OAuth2 support** — automatic token refresh
- ✅ **WASM plugin system** — extensible credential types

**Relationship to Plan:** Vultrino implements **almost exactly what Phase 2-4 of this plan covers**. The proxy service, OpenBao integration, templated responses, and audit logging are all built-in.

**GitHub:** https://github.com/zachyking/vultrino

---

### Agent Gateway — Agentic Proxy for AI Agents and MCP

| Attribute | Value |
|-----------|-------|
| Stars | 1.7k |
| License | Apache-2.0 |
| Language | Rust (80.1%) |
| Self-Hosted | ✅ Yes |
| Sponsor | Linux Foundation |

**Key Features:**
- ✅ **A2A and MCP protocols** — Agent-to-Agent and Model Context Protocol
- ✅ **RBAC system** — role-based access control
- ✅ **Multi-tenant** — isolated resources per tenant
- ✅ **Dynamic configuration** — xDS updates without downtime
- ✅ **Kubernetes support** — via kgateway.dev integration
- ✅ **Legacy API transformation** — OpenAPI → MCP
- ✅ **Built-in UI** — dashboard for exploration
- ✅ **High performance** — Rust-based architecture

**Relationship to Plan:** Agent Gateway is a **comprehensive platform** that includes credential proxying but adds A2A protocol support, multi-tenancy, and Kubernetes orchestration. More complex but more featureful.

**GitHub:** https://github.com/agentgateway/agentgateway

---

## Revised Comparison Table

| Project | Stars | Isolation | Credential Proxy | MCP | Domain Binding | Vault/OpenBao | Self-Hosted |
|---------|-------|-----------|------------------|-----|----------------|---------------|-------------|
| **anthropic-experimental/sandbox-runtime** | 2.9k | Bubblewrap | ❌ No | ❌ No | Partial | ❌ No | ✅ Yes |
| **zachyking/vultrino** | 5 | — | ✅ **Full** | ✅ Yes | ✅ Yes | ❌ Custom | ✅ Yes |
| **agentgateway/agentgateway** | 1.7k | — | ✅ Yes | ✅ Yes | ✅ Yes | ❌ Custom | ✅ Yes |
| **abshkbh/arrakis** | 753 | MicroVM | ❌ No | ❌ No | ❌ No | ❌ No | ✅ Yes |
| **API Stronghold** | — | VM/Container | ✅ Yes | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |

---

## Revised Recommendation

**Option 1: Use Vultrino (simplest)**
- Replaces Phases 2-4 entirely
- Already has MCP integration, credential proxy, audit logging
- Missing: OpenBao integration (uses built-in encrypted storage)
- Add: gVisor sandbox + OpenBao integration

**Option 2: Use Agent Gateway (most features)**
- Comprehensive platform with A2A + MCP
- More complex deployment
- Missing: OpenBao integration
- Add: gVisor sandbox + OpenBao integration

**Option 3: Build custom (this plan)**
- Full control over architecture
- No external dependencies
- Matches original requirements exactly

**Recommended Path:** Evaluate **Vultrino** first—it aligns with ~80% of the planned work and is actively maintained (17 commits, recent activity). Only build custom if Vultrino's encrypted storage model doesn't meet audit/compliance requirements that OpenBao would satisfy.