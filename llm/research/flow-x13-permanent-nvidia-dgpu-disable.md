---
title: "Flow X13 Permanent NVIDIA dGPU Disable - Domain Research"
date: "2026-07-20"
depth: "deep-dive"
request: "dotfiles-724y"
---

## Executive Summary

The current `flowX13` configuration does not permanently remove the NVIDIA display function. It copies NVIDIA's runtime-D3 setup for the three auxiliary PCI functions and leaves the VGA/3D function available under runtime power management (`hosts/flowX13/configuration.nix:214-231`). It also runs `supergfxd` (`hosts/flowX13/configuration.nix:233-234`), whose default mode is Hybrid and whose default hotplug method does not use ASUS `dgpu_disable`. This explains why the current state can still expose or wake the dGPU even though the repository's custom NVIDIA option is disabled.

Current `nixos-hardware` upstream provides exactly the stronger declarative policy requested. At revision `779c32a00155994c86cde8213a8dd4df139d4355` (2026-07-17), `nixosModules.common-gpu-nvidia-disable` blacklists nouveau and the proprietary display modules and applies boot-time udev rules that remove every NVIDIA VGA/3D, audio, xHCI, and UCSI PCI function. The exposed flake module name is verified in `nixos-hardware/flake.nix:471-480`; it is not inferred from Fable's advice.

The recommended implementation direction is to import that upstream module only for `flowX13`, remove the host's duplicate partial udev rules, and disable `services.supergfxd`. Keep Xorg/Wayland on `modesetting` and keep all proprietary NVIDIA enablement off. This is the smallest maintained configuration matching the user's permanent-disable requirement. PCI removal is logical kernel removal, not a platform-independent proof that the physical power rail is off; therefore acceptance must include absence of all NVIDIA PCI functions and modules after cold boot and suspend/resume, plus a controlled battery discharge-rate comparison.

---

## Upstream NixOS Hardware Module

### Current module behavior

The current source is `common/gpu/nvidia/disable.nix` at nixos-hardware revision `779c32a00155994c86cde8213a8dd4df139d4355`.

```nix
# common/gpu/nvidia/disable.nix:7-10
boot.extraModprobeConfig = ''
  blacklist nouveau
  options nouveau modeset=0
'';
```

It then adds four `ACTION=="add"`, `SUBSYSTEM=="pci"` udev rules selected by NVIDIA vendor ID `0x10de` (`common/gpu/nvidia/disable.nix:12-24`):

| PCI class | Function commonly represented | Action |
|---|---|---|
| `0x0c0330` | USB xHCI controller | Set runtime PM to `auto`, then write `1` to `remove` |
| `0x0c8000` | USB Type-C UCSI controller | Set runtime PM to `auto`, then write `1` to `remove` |
| `0x040300` | HDA audio controller | Set runtime PM to `auto`, then write `1` to `remove` |
| `0x03[0-9]*` | VGA/3D/display controller family | Set runtime PM to `auto`, then write `1` to `remove` |

Finally, it blacklists `nouveau`, `nvidia`, `nvidia_drm`, and `nvidia_modeset` (`common/gpu/nvidia/disable.nix:25-30`). The module does not enable bbswitch, call ASUS WMI, set `dgpu_disable`, configure PRIME, or install a switching daemon.

The VGA/3D removal rule was added in upstream commit `defc8e4677936687ea10ed3fbb1d342abdf8249e` (2023-03-04, "Fix disabling Nvidia dGPU"). Additional proprietary modules were blacklisted in `289a5af77e624b29b9efd06de262b324c8018abe` (2023-06-28). The behavior is therefore established upstream behavior rather than a newly proposed local rule.

### Exposed flake API

The current flake export is exactly:

```nix
# nixos-hardware/flake.nix:476-480
common-gpu-nvidia-disable = import ./common/gpu/nvidia/disable.nix;
```

The consumer API is therefore:

```nix
nixos-hardware.nixosModules.common-gpu-nvidia-disable
```

The dotfiles flake currently has no `nixos-hardware` input (`flake.nix:6-93`) and no corresponding output argument (`flake.nix:95-121`), so adopting the flake module requires adding and pinning that input before host import. Directly copying the rules would avoid an input but would duplicate maintained upstream behavior and obscure provenance.

### Assessment

| Aspect | Upstream disable module | Local copied rules |
|---|---|---|
| VGA/3D function | Removed on PCI add | Not removed; runtime PM only |
| Auxiliary functions | All removed | All three removed |
| Nouveau | Blacklist plus `modeset=0` | Blacklisted by custom module |
| Proprietary driver | `nvidia`, `nvidia_drm`, `nvidia_modeset` blacklisted | Only `nvidia` explicitly blacklisted by custom module |
| Runtime switching | None | `supergfxd` enabled |
| Maintenance | Upstream source | Local duplicated fragment |

**Adoption recommendation:** Adopt `nixos-hardware.nixosModules.common-gpu-nvidia-disable` rather than extending the local hand-written rules.

---

## NVIDIA, Nouveau, and NixOS Interactions

### Existing local behavior

When `CUSTOM.hardware.nvidia.enable = false`, the custom module sets `services.xserver.videoDrivers = [ "modesetting" ]` and blacklists `nvidia`, `nouveau`, and `radeon` (`modules/nixos/hardware/nvidia/default.nix:166-176`). The Flow host also explicitly selects `modesetting` and leaves both the custom NVIDIA module and proprietary mode disabled (`hosts/flowX13/configuration.nix:194-207`). Proprietary `hardware.nvidia`, PRIME, CUDA packages, and NVIDIA-specific environment variables are only configured inside the enabled branch (`modules/nixos/hardware/nvidia/default.nix:178-277`).

This means there is no current intentional proprietary NVIDIA configuration on the Flow host. The upstream disable module is compatible with the intended iGPU-only configuration and strengthens its blacklist. The existing `radeon` blacklist is unrelated to disabling NVIDIA and should not be attributed to the upstream module.

### Conflict modes to avoid

An implementation should not simultaneously:

- Import the permanent-disable module and set `services.xserver.videoDrivers = [ "nvidia" ... ]`.
- Enable `hardware.nvidia.prime`, `hardware.nvidia.powerManagement`, persistence, Dynamic Boost, or NVIDIA container wiring for this host.
- Enable nouveau while the PCI display function is removed.
- Keep a GPU switching daemon that can rewrite modprobe policy or rescan removed PCI devices.

The upstream blacklist does not list `nvidia_uvm` or `nvidia_peermem`, but those modules depend on the core `nvidia` module and cannot provide a usable GPU when `nvidia` is blacklisted and the PCI function is absent. Explicitly adding every possible NVIDIA helper is unnecessary unless post-boot evidence shows one loaded independently.

### Nouveau distinction

`hardware.nvidia.open` refers to NVIDIA's open kernel modules, not nouveau. The permanent-disable module blocks both driver families through `nvidia` and `nouveau`; leaving `hardware.nvidia.open` unset is not sufficient by itself. The upstream module's `boot.extraModprobeConfig` also disables nouveau modesetting in addition to the NixOS module blacklist.

**Adoption recommendation:** Keep `modesetting` as the display driver, retain `CUSTOM.hardware.nvidia.enable = false`, import the upstream disable module, and verify no other merged host module enables NVIDIA behavior.

---

## PCI Removal Semantics and Power

### What `remove` proves

Writing non-zero to a PCI device's sysfs `remove` attribute asks the Linux PCI core to remove that device from the kernel device tree. Consequently, successful removal means it disappears from `lspci`, its sysfs PCI node disappears, and no driver can bind to it until firmware/hardware presents it again or a PCI rescan rediscovers it.

It does not, by itself, universally guarantee that a motherboard has cut the physical power rail. Physical D3cold depends on the parent bridge, ACPI methods, firmware, and platform wiring. NVIDIA's current RTD3 documentation states that the chip's lowest power state often requires ACPI and that all one, two, or four functions must cooperate. It identifies the same four function types and requires runtime PM support for every present function.

The upstream module goes beyond NVIDIA's current RTD3 recipe: NVIDIA's automated setup removes auxiliary functions but merely sets runtime PM on the VGA/3D function; nixos-hardware removes the VGA/3D function too. This is appropriate for permanent unavailability but means NVIDIA's driver-managed RTD3 telemetry under `/proc/driver/nvidia/.../power` will not exist and should not be used as the acceptance test.

### Udev behavior and races

The rules run for each matching PCI `add` event. They are vendor/class based rather than tied to `01:00.x`, so they tolerate PCI address changes and cover all NVIDIA functions of those classes. This also means they remove any NVIDIA PCI GPU in the machine, not just one selected device.

Potential caveats:

- A manual or daemon-triggered global PCI rescan can rediscover removed functions. A new `add` event should invoke the same rule again, but there can be a short rediscovery/removal interval.
- Removing display or audio functions that are actively used can blank displays or remove HDMI/DisplayPort audio. Applying at boot while all display selection is pinned to the AMD iGPU minimizes that risk.
- If an NVIDIA-connected display path is required, permanent removal makes it unavailable. Exact Flow X13 port routing varies by model/year and must be tested on this physical unit; generic Flow X13 reports are not strong enough to guarantee every port.
- The model identity and complete pre-change PCI inventory were not available in the repository. The local bus IDs suggest NVIDIA `01:00.0` and AMD `08:00.0` (`modules/nixos/hardware/nvidia/default.nix:67-75`), but validation should capture `lspci -Dnn` before implementation rather than treating those addresses as immutable.
- A BIOS update, Windows dual-boot session, or firmware MUX state can alter ASUS WMI and MUX state. The vendor/class udev rules are less dependent on that state than a runtime switcher, but cannot remove hardware that firmware does not expose to Linux at all or correct a dGPU-only MUX setting needed for the internal panel.

**Adoption recommendation:** Use the generic vendor/class rules through nixos-hardware, but describe the result as permanently unavailable to Linux and verify power empirically rather than promising physical rail-off from sysfs semantics alone.

---

## ASUS Flow X13 and supergfxctl

### Verified upstream behavior

At supergfxctl revision `5d503b1efd41f29f77679513890807c0c0a576fe` (2025-11-08), upstream describes `Integrated` as force-disabling the dGPU but warns that hotplug and ASUS `dgpu_disable` results vary (`README.md:3-17`). It also states that it conflicts with other GPU switchers and warns about stray module blacklists (`README.md:32-39`).

The daemon defaults to `Hybrid` mode and `HotplugType::None` (`src/config.rs:71-85`). With `HotplugType::None`, its action model uses device-tree unbind/remove rather than ASUS hard disable (`src/actions.rs:166-180`, `src/actions.rs:330-338`). A Hybrid-to-Integrated transition stops the display manager, unloads drivers, removes the GPU, rewrites modprobe configuration, and then optionally invokes the configured hotplug mechanism (`src/actions.rs:340-356`). A reverse transition performs a PCI rescan and loads drivers (`src/actions.rs:387-399`).

The ASUS-specific path is `/sys/devices/platform/asus-nb-wmi/dgpu_disable` (`src/special_asus.rs:15-17`). Upstream calls it a hard removal that prevents PCI rescan from finding the dGPU (`src/actions.rs:177-180`), but labels ASUS handling "fiddly" (`src/config.rs:67-68`), waits for WMI availability during boot, and can require a reboot when module setup is missing (`src/special_asus.rs:225-246`).

NixOS's service module installs the daemon's package, udev rules, DBus policy, and systemd service (`nixpkgs/nixos/modules/services/hardware/supergfxd.nix:28-47`). The packaged upstream rules also modify NVIDIA runtime PM on driver bind/unbind (`supergfxctl/data/90-supergfxd-nvidia-pm.rules:1-7`). Keeping the daemon therefore introduces an active policy owner that can rescan and rewrite driver policy, contrary to a permanent declarative disable.

### Flow-specific upstream support

Current nixos-hardware has profiles for newer Flow GV302X and GZ301VU, not the repository's apparent older GV301-era bus layout. The GV302X shared profile enables `supergfxd` by default (`asus/flow/gv302x/shared.nix:60-66`), but that profile targets switchable graphics and does not establish that supergfxctl is reliable for this machine or suitable for permanent disablement. It should not override the user's direct evidence that runtime switching has failed.

ASUS's `asusctl` GitLab repository has migrated future development to OpenGamingCollective (`asusctl/README.md:12-20`). Cardwire is an emerging alternative that blocks access to GPU device nodes using eBPF rather than removing the PCI device, but its own README labels it early development and NVIDIA blocking experimental. It solves unwanted wakeups while retaining RTD3, not the requested permanent hardware absence, so it is not preferable here.

### Assessment

| Approach | Reliability fit | Reversibility | Policy owner | Fit for request |
|---|---|---|---|---|
| nixos-hardware disable module | Static on every boot; no runtime state machine | Rebuild/reboot | NixOS + udev | Best |
| supergfxctl Integrated | Runtime sequence; upstream says results vary | Runtime switch/rescan | Daemon | Rejected by user experience |
| ASUS `dgpu_disable` direct write | Potential hard platform disable, firmware/model dependent | WMI toggle/reboot may be needed | Local custom service/script | Possible fallback only after evidence |
| Cardwire | Prevents userspace wakeups; relies on RTD3 | Runtime | eBPF daemon | Experimental and not permanent removal |

**Adoption recommendation:** Disable `services.supergfxd` for the permanent-disable configuration. Keep ASUS `dgpu_disable` as a separately researched fallback only if complete PCI removal still fails the controlled power test; do not stack both mechanisms initially because that would obscure which one works and complicate recovery.

---

## Post-Reboot Validation Evidence

Validation must be performed after a cold boot into the new generation, not only after `nixos-rebuild switch`, because the old driver/daemon state can survive a live activation.

### Required structural evidence

1. Record the booted generation and kernel: `readlink -f /run/current-system` and `uname -r`.
2. Confirm the runtime switcher is absent: `systemctl is-enabled supergfxd.service` and `systemctl is-active supergfxd.service` must both report disabled/inactive or not found.
3. Confirm no NVIDIA PCI function remains: `lspci -Dnn -d 10de:` must produce no output. This checks all functions, unlike `grep -i nvidia`, which depends on the PCI name database.
4. Confirm known pre-change NVIDIA sysfs nodes are absent: for each NVIDIA BDF captured before implementation, `/sys/bus/pci/devices/<BDF>` must not exist.
5. Confirm no NVIDIA display driver is loaded: `lsmod` must contain none of `nvidia`, `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`, or `nouveau`.
6. Confirm the AMD iGPU owns the active render/display path: `lspci -Dnnk` should show `amdgpu` for the AMD display controller, and the compositor/display session must start normally.
7. Repeat items 3-6 after one suspend/resume cycle. Also inspect `journalctl -b -k` for PCI, udev, amdgpu, nouveau, or NVIDIA errors.
8. Test every external display port and required audio path. Record any port that stops working; this is a hardware-routing acceptance decision, not merely a cosmetic regression.

### Required power evidence

Absence from PCI proves Linux cannot use the dGPU but not the physical wattage. Compare before and after under the same controlled conditions:

- Battery only, same charge range, brightness, refresh rate, radio state, power profile, compositor, and idle applications.
- Wait at least five minutes after login for startup work and battery reporting to settle.
- Sample `/sys/class/power_supply/BAT*/power_now` at a fixed interval for at least 10-20 minutes. Convert microwatts to watts and retain all samples plus median/mean; do not accept a single instantaneous reading.
- Record battery `status` and ensure it is `Discharging`; otherwise `power_now` is not comparable.
- Optionally record PowerTOP's total discharge rate, but do not use its per-device estimates as proof.
- Compare against an equivalently collected pre-change baseline. The user has not specified a numeric watt or runtime target, so research cannot set a pass threshold without Phase 2 elicitation. A material, repeatable reduction and battery runtime no longer constrained to under two hours are the user-facing evidence.

If all PCI/module checks pass but discharge remains high, do not add ASUS WMI writes immediately. First isolate CPU wakeups, display brightness/rate, USB devices, radios, and TLP behavior. If the remaining excess is demonstrably tied to the dGPU power rail, then evaluate a boot-time ASUS `dgpu_disable=1` fallback with a recovery generation and model-specific test.

**Adoption recommendation:** Make the structural checks and controlled discharge comparison explicit UAT evidence. `lspci` alone is necessary but insufficient.

---

## Sources

| Source | Revision/date | Relevance |
|---|---|---|
| [NixOS/nixos-hardware](https://github.com/NixOS/nixos-hardware/blob/779c32a00155994c86cde8213a8dd4df139d4355/common/gpu/nvidia/disable.nix) | `779c32a`, 2026-07-17 | Exact permanent-disable module behavior |
| [nixos-hardware flake exports](https://github.com/NixOS/nixos-hardware/blob/779c32a00155994c86cde8213a8dd4df139d4355/flake.nix#L471-L480) | `779c32a`, 2026-07-17 | Exact `common-gpu-nvidia-disable` API |
| [asus-linux/supergfxctl](https://gitlab.com/asus-linux/supergfxctl) | `5d503b1`, 2025-11-08 | Runtime switching, PCI rescan, and ASUS WMI implementation |
| [NixOS supergfxd module](https://github.com/NixOS/nixpkgs/blob/9ae611a455b90cf061d8f332b977e387bda8e1ca/nixos/modules/services/hardware/supergfxd.nix) | `9ae611a`, 2026-06-10 | NixOS service wiring and installed policy |
| [NVIDIA RTD3 README 580.105.08](https://download.nvidia.com/XFree86/Linux-x86_64/580.105.08/README/dynamicpowermanagement.html) | Driver 580.105.08 | PCI multifunction and D3cold requirements |
| [Linux PCI driver documentation](https://docs.kernel.org/PCI/pci.html) | Current docs retrieved 2026-07-20 | PCI removal/driver lifecycle context |
| [OpenGamingCollective/cardwire](https://github.com/OpenGamingCollective/cardwire) | Current main retrieved 2026-07-20 | Experimental eBPF alternative assessment |
| Local dotfiles | Worktree inspected 2026-07-20 | Current partial rules and NVIDIA/supergfx configuration |

Repositories were cloned and inspected under `/home/minttea/codebases`; no `/nix/store` source trees were searched.

---

## Summary

| Topic Area | Recommendation | Rationale |
|---|---|---|
| Disable mechanism | Adopt nixos-hardware module | Current, maintained, removes all NVIDIA PCI functions |
| Proprietary NVIDIA | Keep disabled | Contradicts permanent removal and can bind/wake device |
| Nouveau | Keep blacklisted | Prevents alternate driver initialization |
| supergfxctl | Disable | Runtime state owner can rescan/re-enable; already unreliable for user |
| ASUS `dgpu_disable` | Defer as fallback | Stronger platform-specific possibility but firmware/model dependent |
| Cardwire | Skip for this request | Experimental NVIDIA support and does not remove hardware |
| Validation | Structural plus measured power evidence | PCI absence alone does not prove physical rail-off |

## Key Takeaways

### Adopt

- Pin and import `nixos-hardware.nixosModules.common-gpu-nvidia-disable` for `flowX13`.
- Remove the duplicate partial Flow udev rules when implementing.
- Disable `supergfxd` and retain AMD `modesetting`/amdgpu operation.
- Require cold-boot, resume, port, module, PCI, and controlled discharge evidence.

### Adapt

- Preserve the existing custom NVIDIA option as disabled, but inspect the evaluated merged configuration to ensure no other module re-enables proprietary NVIDIA behavior.
- Capture actual model, BIOS version, NVIDIA BDF/functions, and display-port routing before implementation.

### Defer

- A model-specific boot-time ASUS `dgpu_disable` mechanism, only if PCI removal succeeds structurally but measured drain remains attributable to the dGPU.

### Skip

- Runtime supergfxctl switching for this permanent-disable goal.
- bbswitch/legacy Optimus paths.
- Cardwire as a replacement for permanent PCI removal.
- Treating one `power_now` sample or `lspci` alone as proof of success.
