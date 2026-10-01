# Debug VM: structure, networking, and security

The debug VM is a standalone NixOS guest that mirrors the runner VM stack for
experiments. A normal user starts it. It needs no root, no tap, no bridge, and
no host configuration change. `scripts/runner-vm-debug` builds, runs, and
stops it.

## Model

### Elements

| Name | Type | Technology | Description |
|---|---|---|---|
| desktop | Deployment Node | NixOS host | The physical machine that runs the debug VM. |
| user session | Deployment Node | systemd user manager | The unprivileged session that starts every process of the debug VM. |
| runner-vm-debug | Deployment Node | NixOS guest, Cloud Hypervisor | The debug guest; runs the container stack under test. |
| cloud-hypervisor | Container | Cloud Hypervisor 52 | The VMM process that owns the guest and its devices. |
| passt | Container | passt 2025_09_19 | Gives the guest its NIC. Forwards one loopback port to it. |
| virtiofsd | Container | virtiofsd 1.13.3 | Serves one host directory to the guest. |
| root shell | Container | sshd | Root login, key only. |
| podman | Container | podman 5.8.6 | The engine under test. |

### Relationships

| Source | Target | Intent | Technology |
|---|---|---|---|
| cloud-hypervisor | passt | attaches the guest NIC to the network backend | vhost-user, unix socket |
| cloud-hypervisor | virtiofsd | mounts the shared directory in the guest | virtiofs, unix socket |

## Deployment

```c4
Deployment diagram: debug VM, local desktop

+== desktop [Deployment Node: NixOS host] =====================================+
|                                                                              |
| +== user session [Deployment Node: systemd user manager] ==================| |
| |                                                                         | |
| |     +------------------------------+                                    | |
| |     | cloud-hypervisor             |                                    | |
| |     | [Container: Cloud Hypervisor] |                                   | |
| |     | Owns the guest and devices.  |                                    | |
| |     +------------------------------+                                    | |
| |                                                                         | |
| |                |                                                        | |
| |                | attaches the guest NIC (vhost-user)                    | |
| |                v                                                        | |
| |     +------------------------------+                                    | |
| |     | passt                        |                                    | |
| |     | [Container: passt]           |                                    | |
| |     | Gives the guest its NIC.     |                                    | |
| |     +------------------------------+                                    | |
| |                                                                         | |
| |                |                                                        | |
| |                | attaches the shared directory (virtiofs)               | |
| |                v                                                        | |
| |     +------------------------------+                                    | |
| |     | virtiofsd                    |                                    | |
| |     | [Container: virtiofsd]       |                                    | |
| |     | Serves one host directory.   |                                    | |
| |     +------------------------------+                                    | |
| |                                                                         | |
| +== user session [Deployment Node: systemd user manager] ==================| |
|                                                                              |
| +== runner-vm-debug [Deployment Node: NixOS guest, Cloud Hypervisor] ======| |
| |                                                                         | |
| |     +------------------------------+                                    | |
| |     | root shell                   |                                    | |
| |     | [Container: sshd]            |                                    | |
| |     | Root login, key only.        |                                    | |
| |     +------------------------------+                                    | |
| |                                                                         | |
| |     +------------------------------+                                    | |
| |     | podman                       |                                    | |
| |     | [Container: podman 5.8.6]    |                                    | |
| |     | The engine under test.       |                                    | |
| |     +------------------------------+                                    | |
| |                                                                         | |
| +== runner-vm-debug [Deployment Node: NixOS guest, Cloud Hypervisor] ======| |
|                                                                              |
+== desktop [Deployment Node: NixOS host] =====================================+

Key:
  Double-line box = deployment node, nested where one runs inside another. Solid box =
  a container instance or an infrastructure node. [Type] = C4 abstraction.
  Arrow = one relationship, read as "source, label (technology), target".
```

## Opening a shell

passt forwards one host port to the guest. The dynamic diagram shows the path.

```c4
Dynamic diagram: open a root shell in the debug VM

+---------------------+
| maintainer          |
| [Person]            |
| Operates the VM.    |
+---------------------+
           |
           | 1. ssh on port 2222 (ssh)
           v
+---------------------+
| passt               |
| [Container: passt]  |
|                     |
+---------------------+
           |
           | 2. forwards the connection (TCP over a NAT network)
           v
+---------------------+
| root shell          |
| [Container: sshd]   |
|                     |
+---------------------+

Key:
  Solid box = element. [Type] = C4 abstraction. Numbered arrow = one interaction, in
  order. Read as "source, N. label (technology), target".
```

## Networking

- passt gives the guest one virtio NIC and answers its DHCP requests. The
  guest address is in passt's private range, 192.168.0.0/24, with the gateway
  at 192.168.0.1. The guest is not on the runner bridge and holds no address
  from it.
- Outbound traffic leaves through passt sockets as the starting user. The host
  needs no NAT rule, no IP forwarding, and no firewall change for the guest.
- Inbound traffic exists only through explicit forwards. The script forwards
  one port: `-t 127.0.0.1/2222:22`. The host binds it on the loopback address
  only.
- virtiofsd serves exactly one directory: the share path in the script,
  `~/.local/share/runner-vm-debug/share`, mounted at `/mnt/share` in the
  guest. The mount is read-write.
- Cloud Hypervisor requires shared guest memory for a vhost-user device. The
  virtiofs share sets that flag, so the share is also a requirement of the
  network path.

Check the state with these commands:

```
ss -ltnp | grep 2222                          # must show 127.0.0.1:2222
./scripts/runner-vm-debug ssh 'ip -br addr'   # guest addresses
```

## Security

- **Reach.** The ssh forward listens on 127.0.0.1 only. No other machine can
  open the connection, and the guest has no other inbound path.
- **Identity.** The guest sshd accepts root by the authorized key named in the
  module. Password login stays off.
- **Privilege.** Every process of the debug VM runs with the permissions of
  the starting user: cloud-hypervisor, passt, and virtiofsd. No process of the
  debug VM holds a root capability, and no host service changes state for it.
- **Confinement inside the guest.** Root in the debug guest is root in that
  guest only. The guest sees no host path except the one virtiofs share, and
  it holds no host credentials.
- **Exposure of the guest.** A process that runs as the starting user can
  reach the guest, because the user owns the ssh key and the loopback port.
  This equals the trust boundary of the machine itself. A stronger boundary
  needs a second user account.
- **Changed host state.** None. The debug VM adds no unit, no device, no rule,
  and no firewall opening to the host.

## Limits

- The guest is behind NAT. A service inside the guest is reachable from the
  host only through a forwarded port, which you add to the script when a debug
  session needs one.
- The nested arrangement for runner experiments (a debug guest that hosts
  further microVMs) is not built yet. When it is, the inner VMs get taps and
  a bridge inside the debug guest, where root is free.
