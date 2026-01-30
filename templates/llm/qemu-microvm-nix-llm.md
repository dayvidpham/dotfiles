# Research: NixOS Sandboxes for Agent-Driven Development

Research for implementing `~/.claude/plans/happy-growing-trinket.md` (Firecracker microVM with 4-12 LLM agents).

---

## Summary

**Updated recommendation:** Use **microvm.nix + QEMU** for your requirements:
- ✅ virtio-fs for performant I/O (LLM transcript writes)
- ✅ VSOCK for host<->guest communication (no external network)
- ✅ NixOS-native, declarative configuration

**Key decision: VM vs Container?**

| Aspect | VM (QEMU/Firecracker) | Container (Podman/Docker) |
|--------|----------------------|---------------------------|
| Isolation | Separate kernel (hardware) | Shared kernel (namespace) |
| Escape difficulty | VM escape = rare, complex | Container escape = more common |
| Startup | ~200-300ms | <100ms |
| I/O overhead | virtio-fs near-native | Native filesystem |
| Network isolation | VSOCK (no TCP/IP stack) | Network namespaces |
| NixOS integration | microvm.nix | virtualisation.oci-containers |
| Complexity | Higher | Lower |

**When to use containers:**
- Trusted code or your own orchestration code
- Sub-100ms startup required
- Simpler setup preferred
- Defense-in-depth via seccomp + rootless + user namespaces

**When to use VMs:**
- Executing LLM-generated code (untrusted)
- Maximum isolation required
- VSOCK-only networking (no TCP/IP attack surface)
- You don't trust seccomp alone to stop kernel exploits

**Recommendation:** For LLM agents executing untrusted code, **VM isolation is safer**. Container escapes via kernel vulnerabilities are more feasible than VM escapes.

---

## Tier 1: VM-Based Isolation (Recommended)

### microvm.nix ⭐ (Already in your plan)
**GitHub:** https://github.com/microvm-nix/microvm.nix

The best NixOS-native solution for your architecture.

**Key features:**
- 8 hypervisors: QEMU, Firecracker, cloud-hypervisor, crosvm, kvmtool, stratovirt, alioth, vfkit
- **VSOCK support:** qemu, crosvm, kvmtool (Firecracker uses AF_UNIX socket mapping)
- **virtiofs/9p shares:** QEMU and cloud-hypervisor (Firecracker lacks share support)
- Read-only squashfs/erofs root with optional overlays
- Balloon memory support

**VSOCK config:**
```nix
microvm.vsock.cid = 3;  # Reserved: 0=hypervisor, 1=loopback, 2=host
```

**Share config:**
```nix
microvm.shares = [{
  source = "/var/lib/workspace";
  mountPoint = "/workspace";
  proto = "virtiofs";  # or "9p"
  tag = "workspace";
}];
```

**Critical note for Firecracker:** No virtiofs/9p support. Use block device volumes instead, or switch to **cloud-hypervisor** (Rust, supports virtiofs, has VSOCK via separate config).

---

### microsandbox
**GitHub:** https://github.com/microsandbox/microsandbox

Rust-based, libkrun microVMs with OCI container compatibility.

**Pros:**
- <200ms startup
- Python/JS/Rust SDKs
- MCP integration for AI agents
- Runs standard Docker images

**Cons:**
- No NixOS integration yet
- Self-hosted only
- Younger project

**Good for:** Quick experimentation, OCI image reuse

---

### E2B
**GitHub:** https://github.com/e2b-dev/E2B
**Website:** https://e2b.dev

Firecracker-based SaaS for AI agent sandboxes.

**Pros:**
- ~150ms startup
- Designed explicitly for LLM agents
- Full SDKs (Python, JS, etc.)
- Handles infrastructure

**Cons:**
- Primarily SaaS (self-host in progress)
- Less NixOS-native

**Good for:** If you want hosted solution or reference architecture

---

## Tier 2: Bubblewrap-Based (Lighter Isolation)

### jail.nix ⭐
**SourceHut:** https://git.sr.ht/~alexdavid/jail.nix
**NixCon 2025 talk:** https://talks.nixcon.org/nixcon-2025/talk/3QH3PZ/

Ergonomic bubblewrap wrappers using combinators.

**Key features:**
- Default-deny security model
- Composable permissions via combinators
- NixOS-native (flake input)

**Usage:**
```nix
inputs.jail-nix.url = "sourcehut:~alexdavid/jail.nix";

# In config:
jail = jail-nix.lib.init pkgs;
sandboxedApp = jail myPackage [
  jail.network
  jail.readonly "/etc"
  jail.rw-bind "/workspace"
];
```

**Good for:** Isolating agent tools (git, curl, etc.) within a VM

---

### nixpak
**GitHub:** https://github.com/nixpak/nixpak

Runtime sandboxing with Flatpak portal integration.

**Key features:**
- D-Bus filtering via xdg-dbus-proxy
- "Sloth values" for runtime path resolution
- GUI app support (Wayland, X11)
- Document Portal for fine-grained file access

**Good for:** Desktop apps, GUI tools in dev environments

---

### Related Bubblewrap Tools

| Project | GitHub | Notes |
|---------|--------|-------|
| nixwrap | https://github.com/rti/nixwrap | CLI wrapper, simpler API |
| nix-bwrapper | https://github.com/Naxdy/nix-bwrapper | Portal support, user-friendly |
| nix-bubblewrap | https://github.com/fgaz/nix-bubblewrap | Low-level integration |

---

## Tier 3: Container-Based

### NixOS Containers
**Docs:** https://nixos.org/manual/nixos/stable/#ch-containers

NixOS-native systemd-nspawn containers.

**Pros:**
- Shares Nix store (efficient)
- Full NixOS config per container
- Declarative

**Cons:**
- Shares kernel (weaker isolation)
- Shares Nix store (secrets concern)

---

### Docker + NixOS (Tembo approach)
**Blog:** https://www.tembo.io/blog/secure-sandboxes-docker-nixos

Use `dockerTools.buildLayeredImage` for minimal images.

**Good for:** Hybrid environments, existing Docker infra

---

## Comparison Matrix

| Solution | Isolation | Startup | virtio-fs | VSOCK | NixOS Native | Best For |
|----------|-----------|---------|-----------|-------|--------------|----------|
| **microvm.nix (QEMU)** | VM (hardware) | ~300ms | ✅ | ✅ | ✅ | **Your use case** |
| microvm.nix (cloud-hypervisor) | VM (hardware) | ~150ms | ✅ | ✅ | ✅ | If QEMU too slow |
| microvm.nix (Firecracker) | VM (hardware) | ~125ms | ❌ | ✅* | ✅ | No shared fs |
| Podman (rootless + seccomp) | Namespace | <100ms | bind | ❌ | ✅ | Trusted code |
| Docker + seccomp | Namespace | <100ms | bind | ❌ | ✅ | Trusted code |
| jail.nix | Namespace | instant | bind | N/A | ✅ | Inside-VM isolation |
| E2B | VM (Firecracker) | ~150ms | ❌ | ❌ | ❌ | SaaS |

*Firecracker VSOCK maps to AF_UNIX sockets on host

### Container Alternative (If You Choose This Path)

If you decide containers are sufficient for your threat model:

```nix
# NixOS module for Podman-based agents
{ config, pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;  # docker CLI compatibility
  };

  # Or with oci-containers for declarative containers
  virtualisation.oci-containers = {
    backend = "podman";
    containers.agent-1 = {
      image = "localhost/agent:latest";
      volumes = [ "/workspace/agent-1:/workspace:rw" ];
      extraOptions = [
        "--security-opt=seccomp=/etc/agent-seccomp.json"
        "--security-opt=no-new-privileges"
        "--cap-drop=ALL"
        "--cap-add=NET_RAW"  # for ICMP if needed
        "--network=none"      # no network
        "--read-only"
        "--tmpfs=/tmp:rw,noexec,nosuid"
      ];
    };
  };
}
```

**Container hardening checklist:**
- [x] `--security-opt=no-new-privileges`
- [x] `--cap-drop=ALL` (add back only what's needed)
- [x] `--network=none` (or custom bridge with firewall)
- [x] `--read-only` with specific tmpfs mounts
- [x] Custom seccomp profile
- [x] Rootless Podman (runs as non-root user)
- [ ] User namespaces (map container root to host non-root)
- [ ] SELinux/AppArmor profile

---

## Recommendations for Your Plan

### 1. Hypervisor Choice: QEMU ⭐

For your requirements (virtio-fs + VSOCK-only), **QEMU is the only option** that supports both:

```nix
# vms/agent-sandbox/configuration.nix
{ config, pkgs, ... }:

{
  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    mem = 4096;  # 4GB

    # VSOCK for host<->guest communication
    vsock.cid = 3;

    # virtio-fs for performant workspace I/O
    shares = [{
      source = "/var/lib/agent-sandbox/workspace";
      mountPoint = "/workspace";
      proto = "virtiofs";
      tag = "workspace";
    }];

    # NO network interfaces - VSOCK only
    interfaces = [];
  };

  # Disable networking entirely inside VM
  networking.useDHCP = false;
  networking.interfaces = {};

  # Guest kernel requirements
  boot.kernelModules = [ "virtio_vsock" ];
}
```

**Hypervisor comparison for your requirements:**

| Hypervisor | virtio-fs | VSOCK | Verdict |
|------------|-----------|-------|---------|
| QEMU | ✅ | ✅ | **Use this** |
| cloud-hypervisor | ✅ | ✅ | Also works |
| Firecracker | ❌ | ✅ | No virtio-fs |

### 2. VSOCK-Only Networking

VSOCK provides host<->guest communication without TCP/IP:

**Host side (orchestrator):**
```python
import socket

# Create VSOCK listener
sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
sock.bind((socket.VMADDR_CID_HOST, 5000))  # CID 2 = host
sock.listen(1)

# Accept connection from guest
conn, addr = sock.accept()
guest_cid, guest_port = addr
```

**Guest side (supervisor):**
```python
import socket

# Connect to host
sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
sock.connect((socket.VMADDR_CID_HOST, 5000))  # CID 2 = host
```

**CID assignment:**
- 0: Hypervisor
- 1: Loopback (guest-to-guest)
- 2: Host
- 3+: Guests (your VM = CID 3)

**Why VSOCK-only?**
- No TCP/IP stack in guest = no network attack surface
- No DNS, no external connections possible
- Agent can only communicate with host via VSOCK
- Host proxies LLM API calls on behalf of agents

### 3. Layered Security

Consider using **jail.nix inside the VM** for defense-in-depth:
```
Host → AppArmor → Firecracker VM → jail.nix per-agent
```

Each agent runs in bubblewrap with only:
- Access to `/workspace/agent-N/`
- Whitelisted tools (git, curl, ripgrep)
- No access to other agents' home dirs

### 4. Network Filtering (Simplified with VSOCK-only)

With VSOCK-only networking, the network filtering from your original plan is **not needed**:
- No TCP/IP stack in guest
- No DNS resolution needed
- Host orchestrator proxies all LLM API calls

The only communication channel is VSOCK port 5000 (or whatever you choose).

---

## Deep Dive: Seccomp Profiles

Seccomp filters limit which syscalls a process can make. This is the deepest layer of defense.

### Approach: Use Docker's Default as Baseline

Docker's default seccomp profile is well-tested and blocks ~44 dangerous syscalls while allowing ~300+ safe ones. Use it as a starting point.

### Profile Format (Docker/OCI compatible)

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    { "names": ["read", "write", "open", "close", "stat", "fstat"], "action": "SCMP_ACT_ALLOW" },
    { "names": ["mmap", "mprotect", "munmap", "brk"], "action": "SCMP_ACT_ALLOW" },
    { "names": ["execve", "exit", "exit_group"], "action": "SCMP_ACT_ALLOW" },
    { "names": ["socket", "connect", "sendto", "recvfrom"], "action": "SCMP_ACT_ALLOW" },
    { "names": ["clone", "fork", "vfork", "wait4"], "action": "SCMP_ACT_ALLOW" }
  ]
}
```

### Syscalls to BLOCK for LLM Agents

| Syscall | Risk | Why Block |
|---------|------|-----------|
| `ptrace` | High | Debug/escape other processes |
| `mount`, `umount` | High | Filesystem manipulation |
| `reboot`, `kexec_load` | High | System control |
| `init_module`, `delete_module` | High | Kernel module loading |
| `pivot_root`, `chroot` | Medium | Escape sandboxes |
| `setns`, `unshare` | Medium | Namespace manipulation |
| `keyctl` | Medium | Kernel keyring access |
| `bpf` | Medium | BPF program loading |
| `perf_event_open` | Medium | Performance monitoring |
| `userfaultfd` | Medium | Used in exploits |

### Syscalls to ALLOW for Dev Tools

For git, curl, python, nodejs, rustc, etc:

| Category | Syscalls |
|----------|----------|
| **File I/O** | read, write, open, openat, close, stat, fstat, lstat, access, readlink, readdir |
| **Memory** | mmap, mprotect, munmap, brk, mremap |
| **Process** | clone, fork, vfork, execve, wait4, exit, exit_group, getpid, getppid |
| **Network** | socket, connect, bind, listen, accept, sendto, recvfrom, shutdown (VSOCK only) |
| **Time** | clock_gettime, gettimeofday, nanosleep |
| **Misc** | ioctl, fcntl, dup, dup2, pipe, select, poll, epoll_* |

### Generating Custom Profiles

Use strace to discover which syscalls your agent actually needs:

```bash
# Record syscalls during agent operation
strace -f -e raw=all -o /tmp/agent-strace.log -- ./agent-runner

# Generate profile from trace
python3 tools/generate_seccomp_policy.py /tmp/agent-strace.log > agent-seccomp.json
```

**Tools:**
- [syscall2seccomp](https://github.com/antitree/syscall2seccomp) - Convert strace to Docker profile
- [seccomp-gen](https://github.com/blacktop/seccomp-gen) - Auto-generate from strace
- [seccomp-tools](https://github.com/david942j/seccomp-tools) - Disasm/asm/emulate profiles

### Applying with jail.nix

```nix
makeJailedAgent = agentId: agentBinary:
  jail "jailed-agent-${toString agentId}" agentBinary (with jail.combinators; [
    # ... other combinators ...

    # Apply seccomp filter
    (add-seccomp ./agent-seccomp.bpf)
  ]);
```

### Testing Strategy

1. Start with `SCMP_ACT_LOG` (log violations, don't kill)
2. Run agent through normal operations
3. Check `/var/log/audit/audit.log` for SECCOMP events
4. Add missing syscalls to allowlist
5. Switch to `SCMP_ACT_ERRNO` or `SCMP_ACT_KILL_PROCESS`

---

## Deep Dive: jail.nix Integration Inside VM

This provides **defense-in-depth**: even if an agent escapes bubblewrap, they're still in the Firecracker VM.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Firecracker VM                                             │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Supervisor (root)                                   │   │
│  │  • Spawns jailed agents via setuid + jail.nix       │   │
│  │  • Routes messages                                   │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │
│  │ Agent 1     │ │ Agent 2     │ │ Agent N     │          │
│  │ uid: 1001   │ │ uid: 1002   │ │ uid: 100N   │          │
│  │ ┌─────────┐ │ │ ┌─────────┐ │ │ ┌─────────┐ │          │
│  │ │bwrap    │ │ │ │bwrap    │ │ │ │bwrap    │ │          │
│  │ │sandbox  │ │ │ │sandbox  │ │ │ │sandbox  │ │          │
│  │ │         │ │ │ │         │ │ │ │         │ │          │
│  │ │/work/1  │ │ │ │/work/2  │ │ │ │/work/N  │ │          │
│  │ └─────────┘ │ │ └─────────┘ │ │ └─────────┘ │          │
│  └─────────────┘ └─────────────┘ └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### jail.nix Flake Input (VM's flake.nix)

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
  };

  outputs = { self, nixpkgs, jail-nix, ... }: {
    nixosConfigurations.agent-sandbox = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        {
          _module.args.jail-nix = jail-nix;
        }
      ];
    };
  };
}
```

### Agent Wrapper Module (VM's configuration.nix)

```nix
{ config, pkgs, lib, jail-nix, ... }:

let
  jail = jail-nix.lib.init pkgs;

  # Common tools available to all agents
  agentTools = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    git
    curl
    wget
    jq
    yq
    ripgrep
    diffutils
    gnutar
    gzip
    unzip
  ];

  # Language runtimes (read-only, from Nix store)
  languageRuntimes = with pkgs; [
    python3
    nodejs
    rustc
    cargo
    go
    gcc
  ];

  # Create jailed wrapper for an agent
  makeJailedAgent = agentId: agentBinary:
    jail "jailed-agent-${toString agentId}" agentBinary (with jail.combinators; [
      # Network for LLM API calls
      network

      # Timezone for logging
      time-zone

      # Mount agent's workspace (read-write)
      (rw-bind "/workspace/agent-${toString agentId}" "/workspace")

      # Mount shared read-only resources
      (ro-bind "/workspace/shared" "/shared")

      # Agent's home directory (read-write, for temp files)
      (rw-bind "/home/agent-${toString agentId}" "/home/agent")

      # Whitelisted tools only
      (add-pkg-deps agentTools)
      (add-pkg-deps languageRuntimes)

      # Prevent symlink escapes
      no-new-session

      # Custom hostname for agent identification
      (set-hostname "agent-${toString agentId}")

      # Forward necessary env vars
      (fwd-env "ANTHROPIC_API_KEY")
      (fwd-env "OPENAI_API_KEY")

      # Seccomp filter (optional, extra hardening)
      # (add-seccomp ./agent-seccomp.json)
    ]);

  # The actual agent binary (claude-code, aider, etc.)
  agentBinary = pkgs.writeShellScriptBin "agent-runner" ''
    # Agent entry point - receives tasks via stdin/stdout
    exec ${pkgs.python3}/bin/python3 /opt/agent/main.py "$@"
  '';

in {
  # Install jailed agents for each UID
  environment.systemPackages = lib.flatten (
    map (n: [
      (makeJailedAgent n agentBinary)
    ]) (lib.range 1 12)
  );

  # Create workspace directories
  systemd.tmpfiles.rules = lib.flatten (
    map (n: [
      "d /workspace/agent-${toString n} 0700 agent-${toString n} agents -"
    ]) (lib.range 1 12)
  ) ++ [
    "d /workspace/shared 0755 root agents -"
  ];
}
```

### Full Combinator Reference

| Category | Combinator | Use Case |
|----------|-----------|----------|
| **Network** | `network` | Enable for LLM API calls |
| **Filesystem** | `ro-bind path target` | Read-only mounts (Nix store, shared) |
| | `rw-bind path target` | Read-write mounts (workspace, home) |
| | `mount-cwd` | Only mount current directory |
| | `tmpfs path` | In-memory temporary storage |
| **Environment** | `fwd-env "VAR"` | Forward API keys |
| | `set-env "VAR" "val"` | Set static values |
| | `try-fwd-env "VAR"` | Forward if exists |
| **Security** | `no-new-session` | Prevent session escapes |
| | `add-seccomp file` | Syscall filtering |
| | `noescape path` | Prevent symlink attacks |
| **Tooling** | `add-pkg-deps [pkgs]` | Whitelist commands |
| **Identity** | `set-hostname name` | Custom hostname |
| | `fake-passwd` | Fake user database |
| **Time** | `time-zone` | Forward timezone |

### Supervisor Integration

The supervisor spawns agents using the jailed wrapper:

```python
# supervisor.py (simplified)
import subprocess
import os

def spawn_agent(agent_id: int, task: dict) -> subprocess.Popen:
    """Spawn a jailed agent process."""
    env = os.environ.copy()
    env["AGENT_TASK"] = json.dumps(task)

    # The jailed wrapper handles all sandboxing
    return subprocess.Popen(
        [f"/run/current-system/sw/bin/jailed-agent-{agent_id}"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        user=f"agent-{agent_id}",  # setuid to agent user
        cwd=f"/workspace/agent-{agent_id}",
    )
```

### Security Layers Summary

| Layer | Technology | Protects Against |
|-------|-----------|------------------|
| 1. Host | AppArmor | VM escape |
| 2. VM | Firecracker KVM | Kernel exploits |
| 3. User | Unix UIDs | Agent crosstalk |
| 4. Namespace | bubblewrap | Filesystem escape |
| 5. Network | nftables | Exfiltration |
| 6. Syscall | seccomp (optional) | Kernel attacks |

### Per-Project Tool Customization

Agents working on specific projects can have additional tools:

```nix
# For a Go project agent
makeJailedAgent 1 agentBinary // (with jail.combinators; [
  (add-pkg-deps [
    pkgs.go
    pkgs.gopls
    pkgs.golangci-lint
    pkgs.go-task
  ])
])

# For a Rust project agent
makeJailedAgent 2 agentBinary // (with jail.combinators; [
  (add-pkg-deps [
    pkgs.rustc
    pkgs.cargo
    pkgs.rust-analyzer
    pkgs.clippy
  ])
])
```

---

## Deep Dive: Host Orchestrator Design

The host orchestrator manages VM lifecycle, dispatches tasks to agents, and collects results.

### Architecture Overview

```
┌────────────────────────────────────────────────────────────────────────────┐
│  Host                                                                       │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Orchestrator (Python/Rust)                                          │  │
│  │                                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │  │
│  │  │ Task Queue  │  │ VSOCK Mgr   │  │ Results DB  │                  │  │
│  │  │ (priority)  │  │ (async I/O) │  │ (SQLite)    │                  │  │
│  │  └─────────────┘  └──────┬──────┘  └─────────────┘                  │  │
│  │                          │                                           │  │
│  │                    ┌─────┴─────┐                                     │  │
│  │                    │ LLM Proxy │  ← Proxies API calls for agents     │  │
│  │                    └───────────┘                                     │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                          │ VSOCK                                           │
│  ┌───────────────────────┼───────────────────────────────────────────────┐│
│  │  VM (QEMU)            │                                               ││
│  │                  ┌────┴────┐                                          ││
│  │                  │Supervisor│                                          ││
│  │                  └────┬────┘                                          ││
│  │        ┌──────────────┼──────────────┐                                ││
│  │   ┌────┴────┐   ┌─────┴────┐   ┌─────┴────┐                          ││
│  │   │ Agent 1 │   │ Agent 2  │   │ Agent N  │                          ││
│  │   └─────────┘   └──────────┘   └──────────┘                          ││
│  └───────────────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────────────────┘
```

### Message Protocol (JSON-RPC style)

```python
# Message format
@dataclass
class Message:
    id: str           # Unique message ID
    type: str         # "task", "result", "llm_request", "llm_response", "heartbeat"
    agent_id: int     # Which agent
    payload: dict     # Task/result data

# Example task
{
    "id": "task-001",
    "type": "task",
    "agent_id": 1,
    "payload": {
        "action": "execute_code",
        "code": "print('hello')",
        "language": "python",
        "timeout_ms": 30000
    }
}

# Example LLM request (agent asks orchestrator to proxy)
{
    "id": "llm-001",
    "type": "llm_request",
    "agent_id": 1,
    "payload": {
        "model": "claude-sonnet-4-20250514",
        "messages": [...],
        "max_tokens": 4096
    }
}
```

### Python Orchestrator (asyncio + VSOCK)

```python
# orchestrator.py
import asyncio
import socket
import json
from dataclasses import dataclass, asdict
from typing import Dict, Callable
import anthropic

CID_HOST = 2  # socket.VMADDR_CID_HOST
VM_CID = 3    # Your VM's CID
VSOCK_PORT = 5000

class Orchestrator:
    def __init__(self):
        self.pending_tasks: Dict[str, asyncio.Future] = {}
        self.anthropic = anthropic.Anthropic()
        self.writer = None
        self.reader = None

    async def connect_to_vm(self):
        """Establish VSOCK connection to VM supervisor."""
        loop = asyncio.get_event_loop()
        sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        sock.setblocking(False)

        # Connect to VM's supervisor
        await loop.sock_connect(sock, (VM_CID, VSOCK_PORT))

        self.reader, self.writer = await asyncio.open_connection(sock=sock)
        print(f"Connected to VM CID={VM_CID}")

    async def send_message(self, msg: dict):
        """Send JSON message over VSOCK."""
        data = json.dumps(msg).encode() + b'\n'
        self.writer.write(data)
        await self.writer.drain()

    async def receive_messages(self):
        """Process incoming messages from VM."""
        while True:
            line = await self.reader.readline()
            if not line:
                break

            msg = json.loads(line.decode())
            await self.handle_message(msg)

    async def handle_message(self, msg: dict):
        """Route message to appropriate handler."""
        msg_type = msg.get("type")

        if msg_type == "result":
            # Agent completed a task
            task_id = msg.get("id")
            if task_id in self.pending_tasks:
                self.pending_tasks[task_id].set_result(msg["payload"])

        elif msg_type == "llm_request":
            # Agent needs LLM API call - proxy it
            response = await self.proxy_llm_request(msg)
            await self.send_message(response)

        elif msg_type == "heartbeat":
            # Agent health check
            await self.send_message({"type": "heartbeat_ack", "id": msg["id"]})

        elif msg_type == "transcript":
            # Agent wrote transcript - it's already on disk via virtio-fs
            # Just log/acknowledge
            print(f"Agent {msg['agent_id']} wrote transcript: {msg['payload']['path']}")

    async def proxy_llm_request(self, msg: dict) -> dict:
        """Proxy LLM API request from agent to Anthropic."""
        payload = msg["payload"]

        # Make API call on behalf of agent
        response = self.anthropic.messages.create(
            model=payload["model"],
            messages=payload["messages"],
            max_tokens=payload.get("max_tokens", 4096)
        )

        return {
            "id": msg["id"],
            "type": "llm_response",
            "agent_id": msg["agent_id"],
            "payload": {
                "content": response.content[0].text,
                "usage": {
                    "input_tokens": response.usage.input_tokens,
                    "output_tokens": response.usage.output_tokens
                }
            }
        }

    async def dispatch_task(self, agent_id: int, task: dict) -> dict:
        """Send task to agent and wait for result."""
        task_id = f"task-{uuid.uuid4()}"

        msg = {
            "id": task_id,
            "type": "task",
            "agent_id": agent_id,
            "payload": task
        }

        # Create future for result
        future = asyncio.get_event_loop().create_future()
        self.pending_tasks[task_id] = future

        # Send task
        await self.send_message(msg)

        # Wait for result
        result = await future
        del self.pending_tasks[task_id]

        return result

    async def run(self):
        """Main orchestrator loop."""
        await self.connect_to_vm()

        # Start message receiver
        receiver_task = asyncio.create_task(self.receive_messages())

        # Example: dispatch tasks to agents
        results = await asyncio.gather(
            self.dispatch_task(1, {"action": "analyze", "file": "/workspace/src/main.py"}),
            self.dispatch_task(2, {"action": "test", "suite": "unit"}),
            self.dispatch_task(3, {"action": "lint", "path": "/workspace/src/"})
        )

        print(f"Results: {results}")

if __name__ == "__main__":
    orchestrator = Orchestrator()
    asyncio.run(orchestrator.run())
```

### VM Supervisor (Inside Guest)

```python
# supervisor.py (runs inside VM)
import asyncio
import socket
import json
import subprocess
import os

CID_HOST = 2  # socket.VMADDR_CID_HOST
LISTEN_PORT = 5000

class Supervisor:
    def __init__(self, num_agents: int = 12):
        self.num_agents = num_agents
        self.agent_processes: Dict[int, subprocess.Popen] = {}

    async def start_server(self):
        """Listen for connections from host orchestrator."""
        loop = asyncio.get_event_loop()
        sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        sock.bind((socket.VMADDR_CID_ANY, LISTEN_PORT))
        sock.listen(1)
        sock.setblocking(False)

        print(f"Supervisor listening on VSOCK port {LISTEN_PORT}")

        while True:
            conn, addr = await loop.sock_accept(sock)
            asyncio.create_task(self.handle_connection(conn, addr))

    async def handle_connection(self, conn, addr):
        """Handle orchestrator connection."""
        reader, writer = await asyncio.open_connection(sock=conn)

        while True:
            line = await reader.readline()
            if not line:
                break

            msg = json.loads(line.decode())
            response = await self.handle_message(msg)

            if response:
                writer.write(json.dumps(response).encode() + b'\n')
                await writer.drain()

    async def handle_message(self, msg: dict) -> dict:
        """Route message to agent or handle internally."""
        msg_type = msg.get("type")

        if msg_type == "task":
            return await self.dispatch_to_agent(msg)

        elif msg_type == "llm_response":
            # Forward LLM response to waiting agent
            return await self.forward_to_agent(msg)

        return None

    async def dispatch_to_agent(self, msg: dict) -> dict:
        """Run task in jailed agent process."""
        agent_id = msg["agent_id"]

        # Spawn jailed agent process
        proc = subprocess.Popen(
            [f"/run/current-system/sw/bin/jailed-agent-{agent_id}"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            user=f"agent-{agent_id}",
            cwd=f"/workspace/agent-{agent_id}",
            env={
                "AGENT_ID": str(agent_id),
                "TASK": json.dumps(msg["payload"])
            }
        )

        # Wait for result (with timeout)
        stdout, stderr = proc.communicate(timeout=msg["payload"].get("timeout_ms", 30000) / 1000)

        return {
            "id": msg["id"],
            "type": "result",
            "agent_id": agent_id,
            "payload": {
                "success": proc.returncode == 0,
                "stdout": stdout.decode(),
                "stderr": stderr.decode(),
                "exit_code": proc.returncode
            }
        }

if __name__ == "__main__":
    supervisor = Supervisor()
    asyncio.run(supervisor.start_server())
```

### Rust Alternative (tokio-vsock)

For production, consider Rust with [tokio-vsock](https://github.com/rust-vsock/tokio-vsock):

```rust
// Cargo.toml
// [dependencies]
// tokio-vsock = "0.5"
// tokio = { version = "1", features = ["full"] }
// serde = { version = "1", features = ["derive"] }
// serde_json = "1"

use tokio_vsock::{VsockListener, VsockStream};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

const LISTEN_PORT: u32 = 5000;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let listener = VsockListener::bind(libc::VMADDR_CID_ANY, LISTEN_PORT)?;

    loop {
        let (stream, addr) = listener.accept().await?;
        tokio::spawn(handle_connection(stream));
    }
}

async fn handle_connection(stream: VsockStream) {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = String::new();

    while reader.read_line(&mut line).await.unwrap() > 0 {
        let msg: serde_json::Value = serde_json::from_str(&line).unwrap();
        // Process message...
        line.clear();
    }
}
```

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Protocol | JSON-RPC over VSOCK | Human-readable, easy debugging |
| LLM API calls | Host proxies | No network stack needed in VM |
| Task dispatch | Async with futures | Handle multiple agents concurrently |
| Agent spawn | Per-task process | Clean state, resource limits |
| Transcripts | virtio-fs direct write | Immediate host visibility |
| Heartbeats | Periodic ping/pong | Detect hung agents |

---

## Deep Dive: tmux Integration

tmux provides session persistence, pane management, and interactive debugging for the agent sandbox.

### Architecture with tmux

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Host (tmux session: sandbox)                                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Pane 0: Orchestrator        │ Pane 1: VM Console      │ Pane 2: Logs   ││
│  │ $ python orchestrator.py    │ $ microvm -c agent-vm   │ $ tail -f ...  ││
│  │                             │                         │                 ││
│  │ [Connected to VM]           │ [VM booted]             │ [agent-1] task ││
│  │ [Dispatched task-001]       │                         │ [agent-2] done ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │ Pane 3: Agent 1 (attach)    │ Pane 4: Agent 2 (attach)  │ ...          ││
│  │ $ socat - VSOCK:3:6001      │ $ socat - VSOCK:3:6002    │              ││
│  │                             │                            │              ││
│  │ [Interactive debugging]     │ [Interactive debugging]    │              ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1. Host tmux Session Setup

```bash
#!/bin/bash
# start-sandbox.sh - Start the complete sandbox environment in tmux

SESSION="sandbox"

# Create session with orchestrator in first pane
tmux new-session -d -s "$SESSION" -n "main" "python orchestrator.py"

# Split for VM console
tmux split-window -h -t "$SESSION:main" "microvm -c agent-sandbox"

# Split for logs
tmux split-window -v -t "$SESSION:main.1" "tail -f /var/lib/agent-sandbox/workspace/*/transcript.jsonl"

# Create window for agent monitoring
tmux new-window -t "$SESSION" -n "agents"

# Split into panes for each agent (up to 4 visible)
for i in {1..4}; do
    if [ $i -eq 1 ]; then
        tmux send-keys -t "$SESSION:agents" "# Agent $i monitor" Enter
    else
        tmux split-window -t "$SESSION:agents"
        tmux send-keys "# Agent $i monitor" Enter
    fi
done
tmux select-layout -t "$SESSION:agents" tiled

# Create window for interactive debugging
tmux new-window -t "$SESSION" -n "debug"

# Attach to session
tmux attach -t "$SESSION"
```

### 2. tmux Inside the VM (Supervisor)

The supervisor can use tmux to manage agent processes:

```python
# supervisor_tmux.py - tmux-based supervisor inside VM
import subprocess
import os

class TmuxSupervisor:
    def __init__(self, session_name: str = "agents"):
        self.session = session_name
        self._create_session()

    def _create_session(self):
        """Create tmux session for agents."""
        subprocess.run([
            "tmux", "new-session", "-d", "-s", self.session
        ], check=False)  # Ignore if exists

    def spawn_agent(self, agent_id: int, task: dict) -> str:
        """Spawn agent in a new tmux window."""
        window_name = f"agent-{agent_id}"

        # Create window for agent
        subprocess.run([
            "tmux", "new-window", "-t", self.session,
            "-n", window_name,
            f"jailed-agent-{agent_id}"  # The jailed binary
        ])

        # Send task via stdin
        task_json = json.dumps(task)
        subprocess.run([
            "tmux", "send-keys", "-t", f"{self.session}:{window_name}",
            task_json, "Enter"
        ])

        return window_name

    def attach_to_agent(self, agent_id: int):
        """Attach to agent's tmux window for debugging."""
        subprocess.run([
            "tmux", "select-window", "-t", f"{self.session}:agent-{agent_id}"
        ])

    def capture_output(self, agent_id: int) -> str:
        """Capture agent's terminal output."""
        result = subprocess.run([
            "tmux", "capture-pane", "-t", f"{self.session}:agent-{agent_id}",
            "-p"  # Print to stdout
        ], capture_output=True, text=True)
        return result.stdout

    def kill_agent(self, agent_id: int):
        """Kill agent's tmux window."""
        subprocess.run([
            "tmux", "kill-window", "-t", f"{self.session}:agent-{agent_id}"
        ])
```

### 3. Interactive Agent Shell Access

For debugging, provide interactive shell access via VSOCK:

```python
# In supervisor - expose debug shell on separate VSOCK port per agent
AGENT_DEBUG_PORT_BASE = 6000  # Agent 1 = 6001, Agent 2 = 6002, etc.

async def start_debug_shell(agent_id: int):
    """Start interactive shell for debugging agent."""
    port = AGENT_DEBUG_PORT_BASE + agent_id

    # Listen on VSOCK port for debug connections
    sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    sock.bind((socket.VMADDR_CID_ANY, port))
    sock.listen(1)

    print(f"Debug shell for agent-{agent_id} on VSOCK port {port}")

    conn, addr = sock.accept()

    # Spawn interactive shell in agent's jail
    proc = subprocess.Popen(
        [f"jailed-agent-{agent_id}", "--shell"],  # Shell mode
        stdin=conn.fileno(),
        stdout=conn.fileno(),
        stderr=conn.fileno(),
        user=f"agent-{agent_id}",
        cwd=f"/workspace/agent-{agent_id}"
    )
    proc.wait()
```

**From host, connect to debug shell:**
```bash
# Connect to agent 1's debug shell
socat - VSOCK-CONNECT:3:6001

# Or in a tmux pane
tmux send-keys -t sandbox:debug "socat - VSOCK-CONNECT:3:6001" Enter
```

### 4. Real-time Agent Monitoring

Monitor all agents' output in real-time:

```bash
# monitor-agents.sh - Monitor all agent transcripts in tmux panes
#!/bin/bash

SESSION="sandbox"
WORKSPACE="/var/lib/agent-sandbox/workspace"

# Create monitoring window
tmux new-window -t "$SESSION" -n "monitor"

# One pane per agent, tailing their transcript
for i in {1..4}; do
    if [ $i -eq 1 ]; then
        tmux send-keys -t "$SESSION:monitor" \
            "tail -f $WORKSPACE/agent-$i/transcript.jsonl | jq -c ." Enter
    else
        tmux split-window -t "$SESSION:monitor"
        tmux send-keys \
            "tail -f $WORKSPACE/agent-$i/transcript.jsonl | jq -c ." Enter
    fi
done

tmux select-layout -t "$SESSION:monitor" tiled
```

### 5. NixOS tmux Configuration

Add tmux to the VM image:

```nix
# vms/agent-sandbox/configuration.nix
{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    tmux
    socat  # For VSOCK debugging
    jq     # For JSON parsing
  ];

  # tmux configuration
  programs.tmux = {
    enable = true;
    extraConfig = ''
      # Status bar showing agent activity
      set -g status-right '#(cat /tmp/agent-status 2>/dev/null || echo "no agents")'

      # Easy pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # Quick agent window creation
      bind A command-prompt -p "Agent ID:" "new-window -n 'agent-%1' 'jailed-agent-%1'"
    '';
  };

  # Supervisor service with tmux
  systemd.services.supervisor = {
    description = "Agent Supervisor";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "forking";
      ExecStart = "${pkgs.tmux}/bin/tmux new-session -d -s agents -n supervisor 'python /opt/supervisor/main.py'";
      ExecStop = "${pkgs.tmux}/bin/tmux kill-session -t agents";
      Restart = "always";
    };
  };
}
```

### 6. Host-side tmux Keybindings

Add keybindings for quick sandbox management:

```bash
# ~/.tmux.conf additions for sandbox management

# Prefix + s = show sandbox session
bind s switch-client -t sandbox

# Prefix + v = connect to VM console
bind v send-keys -t sandbox:main.1 "" Enter

# Prefix + o = show orchestrator
bind o select-window -t sandbox:main

# Prefix + a = show agents
bind a select-window -t sandbox:agents

# Prefix + d = show debug
bind d select-window -t sandbox:debug

# Prefix + 1-9 = attach to agent debug shell
bind 1 send-keys -t sandbox:debug "socat - VSOCK-CONNECT:3:6001" Enter
bind 2 send-keys -t sandbox:debug "socat - VSOCK-CONNECT:3:6002" Enter
bind 3 send-keys -t sandbox:debug "socat - VSOCK-CONNECT:3:6003" Enter
```

### SSH + tmux Persistence

When SSHing to the host, attach to existing session:

```bash
# ~/.bashrc or ~/.zshrc on host
sandbox() {
    # Attach to existing sandbox session, or create new one
    tmux attach -t sandbox 2>/dev/null || ./start-sandbox.sh
}
```

### tmux Integration Summary

| Use Case | Implementation |
|----------|----------------|
| Orchestrator persistence | Host tmux session, survives SSH disconnect |
| Agent monitoring | Panes tailing transcript files via virtio-fs |
| VM console | Pane running `microvm -c agent-sandbox` |
| Interactive debugging | VSOCK debug ports + socat in tmux panes |
| Supervisor management | tmux inside VM managing agent windows |
| Quick navigation | Custom keybindings for session/window switching |

### Future Enhancements

1. **Temporal integration** - Use Temporal for durable workflows
2. **Redis task queue** - Distribute across multiple VMs
3. **Prometheus metrics** - Monitor agent performance
4. **gRPC** - Binary protocol for better performance

---

## References

### Primary Sources
- [microvm.nix](https://github.com/microvm-nix/microvm.nix)
- [microvm.nix options](https://microvm-nix.github.io/microvm.nix/microvm-options.html)
- [jail.nix](https://git.sr.ht/~alexdavid/jail.nix)
- [nixpak](https://github.com/nixpak/nixpak)
- [Firecracker VSOCK docs](https://github.com/firecracker-microvm/firecracker/blob/main/docs/vsock.md)

### Articles & Tutorials
- [How I Run LLM Agents in a Secure Nix Sandbox](https://dev.to/andersonjoseph/how-i-run-llm-agents-in-a-secure-nix-sandbox-1899)
- [Tembo: Building Secure Sandboxes with Docker and NixOS](https://www.tembo.io/blog/secure-sandboxes-docker-nixos)
- [Application Isolation using NixOS Containers](https://msucharski.eu/posts/application-isolation-nixos-containers/)
- [Vibe Coding Safely with OpenCode and NixOS](https://grigio.org/vibe-coding-safely-the-ultimate-guide-to-ai-development-with-opencode-and-nixos-via-docker-nixuser/)

### Curated Lists
- [awesome-sandbox (AI code execution)](https://github.com/restyler/awesome-sandbox)

### Seccomp Tools
- [syscall2seccomp](https://github.com/antitree/syscall2seccomp) - Convert strace to Docker profile
- [seccomp-gen](https://github.com/blacktop/seccomp-gen) - Auto-generate from strace
- [seccomp-tools](https://github.com/david942j/seccomp-tools) - Disasm/asm/emulate profiles
- [rust-vmm/seccompiler](https://github.com/rust-vmm/seccompiler) - Rust library (used by Firecracker)
- [Cloudflare sandbox](https://github.com/cloudflare/sandbox) - Simple env-var based seccomp
- [Docker default seccomp](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json) - Reference profile

### VSOCK & Orchestration
- [VSOCK man page](https://www.man7.org/linux/man-pages/man7/vsock.7.html)
- [VSOCK Python examples](https://gist.github.com/nrdmn/7971be650919b112343b1cb2757a3fe6)
- [tokio-vsock (Rust async)](https://github.com/rust-vsock/tokio-vsock)
- [vhost-device-vsock](https://github.com/rust-vmm/vhost-device/tree/main/vhost-device-vsock)
- [Scheduler Agent Supervisor pattern (Azure)](https://learn.microsoft.com/en-us/azure/architecture/patterns/scheduler-agent-supervisor)
- [firecracker-rs-sdk](https://crates.io/crates/firecracker-rs-sdk)

### Community Discussions
- [Claude Code and security isolation - NixOS Discourse](https://discourse.nixos.org/t/claude-code-and-security-isolation/71543)
- [nix-shell container isolation feature request](https://github.com/NixOS/nix/issues/8207)
- [Jessfraz: How to use new Docker Seccomp profiles](https://blog.jessfraz.com/post/how-to-use-new-docker-seccomp-profiles/)
