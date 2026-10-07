---
name: systemd-services
description: >-
  Writing correct systemd units and NixOS service modules — ordering,
  readiness, dependencies, and health. Use this whenever you create or edit a
  systemd service, a NixOS module defining services.* / systemd.services.*, or
  debug a unit that starts too early, races a socket, crash-loops with a bare
  status=127, or waits using sleep/poll loops. Also use it when wiring one
  service to depend on another (After=/Requires=/Wants=), when something must
  be "up" before a dependent starts, or when adding watchdogs/health checks.
  Erring toward using it is fine: most service bugs are ordering/readiness bugs.
---

# Writing systemd services and NixOS modules

## The one idea that prevents most bugs

**"Started" and "ready" are different.** systemd ordering (`After=`/`Before=`)
only orders *start jobs*. For `Type=simple`, a unit's start job completes as soon
as its process is `exec`'d — often long before it is useful. So
`After=foo.service` does **not** mean "foo is ready"; it means "foo's process has
been spawned." A dependent that needs foo usable (socket listening, port bound,
file written, IPC accepting) must make systemd *know* foo is ready.

Polling and `sleep`-and-hope are the #1 source of flaky services: they pay the
worst-case delay every boot, they still race (the thing may not be ready when the
loop exits), and they hide failure (a loop that times out usually just proceeds
anyway). A readiness signal is exact, fast, and fails loudly.

## The readiness ladder — take the highest rung that applies

1. **Socket activation** (`systemd.sockets`). If the thing you're waiting for is
   "a socket/port exists", let systemd own the socket and hand it to the daemon on
   first connection. Races vanish — systemd creates the socket before anything
   that might connect. Best for TCP/UDP ports and UNIX stream sockets.
2. **`Type=notify` + `sd_notify(READY=1)`.** The daemon — or a small wrapper —
   declares readiness. Dependents ordered `After=` then genuinely start after
   readiness. This is the general answer for a long-running daemon that opens
   resources at start (compositors, gateways, anything you're tempted to "wait
   for"). If the daemon can't notify itself, wrap it: start it as a child, wait
   for the real condition, `systemd-notify --ready`, then `wait`.
3. **`ExecStartPre` that only does setup** (mkdir, migrations, fetch a key).
   Fine — it isn't waiting on *another* unit; systemd blocks the start job until
   it returns. Keep it deterministic and fast. Never turn it into a poll loop for
   another service.
4. **`systemd.path`** when the trigger is "a file/dir appeared" (`PathExists=`,
   `PathChanged=`). Event-driven, not a poll.
5. **Last resort: a bounded `ExecStartPre` wait.** Only with no signal available
   and no way to add one. Then wait for the *right* condition, **fail** the unit
   on timeout (don't proceed), keep the timeout short, and document why. Repeated
   trips here mean you should fix the producer to notify instead.

### Waiting for a UNIX socket correctly
`[ -S "$path" ]` is **not** enough — the socket file can exist before the
listener calls `listen()`. Check it is actually listening, e.g.
`ss -xl | grep -qF " $path"`. Better: don't wait at all (rung 1 or 2). Same for
TCP — a port can be bound but not accepting; prefer socket activation.

## Ordering vs. dependency (don't conflate them)
- `After=` / `Before=` — **ordering only**, no dependency. Cheap and safe.
- `Wants=` — soft dependency; pulled in, failure ignored.
- `Requires=` — hard dependency; if the dep fails/stops, this stops too.
- `BindsTo=` — like `Requires=`, plus stop if the dep *disappears*.
- `PartOf=` — restart/stop propagation upward.

Pair `After=` (ordering) with `Requires=`/`Wants=` (dependency) when you need both
"dep present" and "start after it". `After=` alone will not start the dependency.

## Health, not just readiness
Readiness is one-time; health is ongoing. If the service can hang while still
"running", add `WatchdogSec=<n>` and have the service send
`sd_notify(WATCHDOG=1)` on an interval shorter than it. Feed the watchdog from a
**real probe** (an IPC round-trip), not an "am I alive" ping, or it won't detect
the hang you care about. One process can do both: `READY=1` once, then
`WATCHDOG=1` periodically.

## Restart and failure
- `Restart=on-failure` for crash recovery; `Restart=always` for daemons that must
  always run.
- `RestartSec=` to avoid hot loops; `StartLimitIntervalSec=`/`StartLimitBurst=`
  to cap flapping. For must-keep-retrying units, `StartLimitIntervalSec = 0`.
- Make failures **visible**: a unit that can't reach readiness should fail its
  start job, not silently serve a broken state.

## NixOS module pitfalls (learned the hard way)
- **`writeShellApplication` + `runtimeInputs` = PATH.** Every command your script
  runs must be in `runtimeInputs` or an absolute store path. A missing tool is
  `exit 127`, which systemd shows as a bare `status=127` and **no message**.
  Example: the nixpkgs `sway` wrapper falls back to `dbus-run-session`, which
  execs `dbus-daemon` *by name* — so a unit that runs `sway` needs `pkgs.dbus` on
  PATH or it crash-loops with `failed to execute message bus daemon`.
- **Flakes only see git-tracked files.** A new module directory is invisible to
  `nix eval/build .#…` until `git add`ed; otherwise you get
  `path '…' does not exist`.
- **`nix eval` does not build.** It resolves store paths but doesn't
  instantiate/realise them, so you can't inspect a built wrapper afterward.
  Use `nix build` / `nix-store -r`, or just rebuild.
- **Match the running systemd** — call `${config.systemd.package}/bin/systemd-notify`,
  not a random PATH entry.
- **Isolate sessions.** Give each its own `XDG_RUNTIME_DIR` (Wayland socket names
  collide) and a **private D-Bus session bus** when it launches apps — otherwise
  single-instance services (Firefox's D-Bus remote, `xdg-desktop-portal`, which
  is one-per-bus) get stolen across sessions.
- **Seatless services.** A system service has no logind seat; things expecting one
  (libinput/libseat/portals) may need `WLR_LIBINPUT_NO_DEVICES=1` or a private
  bus. Prefer `StateDirectory=`/`RuntimeDirectory=` over hand-rolled `mkdir` —
  systemd creates, owns, and cleans them.
- **Capabilities.** `AmbientCapabilities=`/`CapabilityBoundingSet=` (or NixOS
  `security.wrappers`). Note `systemd-notify` invoked from a wrapper is a *child
  process*, so `NotifyAccess=all` (not `main`) is required for it to count.

## Service module template (NixOS)

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.CUSTOM.services.<name>;
  inherit (lib) mkIf mkEnableOption mkOption types getExe;

  wrapper = pkgs.writeShellApplication {
    name = "<name>";
    runtimeInputs = [ pkgs.coreutils pkgs.dbus /* every tool the script runs */ ];
    text = ''
      set -eu
      <start the real process as a child if you must signal readiness>
      <wait for the RIGHT condition: listening, not merely present>
      ${config.systemd.package}/bin/systemd-notify --ready
      wait
    '';
  };
in {
  options.CUSTOM.services.<name> = {
    enable = mkEnableOption "<name>";
  };
  config = mkIf cfg.enable {
    systemd.services.<name> = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";        # readiness signal, not Type=simple + polling
        NotifyAccess = "all";   # required when systemd-notify is a child
        # WatchdogSec = 30;
        ExecStart = getExe wrapper;
        Restart = "always";
        RestartSec = 2;
      };
    };
  };
}
```

## Anti-patterns → the fix

| Anti-pattern | Why it's wrong | Fix |
|---|---|---|
| `ExecStartPre` with `while ! …; sleep` for another unit | polls, slow, races, hides failure | `Type=notify` or socket activation |
| `After=foo` and assuming foo is ready | ordering ≠ readiness | make foo `Type=notify`, or activate its socket |
| `[ -S socket ]` as "it's up" | file exists before `listen()` | `ss -xl` check, or socket activation |
| `sleep 5` to "let it come up" | worst case every boot, still racy | readiness signal / bounded wait that fails |
| Retry loop that proceeds on timeout | silent failure | fail the start job on timeout |
| `NotifyAccess=main` with `systemd-notify` CLI | notify comes from a child, ignored | `NotifyAccess=all` |
| Cross-session app launch without a private bus | single-instance services get stolen | separate bus + `XDG_RUNTIME_DIR` |

## Checklist before shipping a unit
- [ ] Anything depending on readiness uses `Type=notify` or socket activation — no sleep/poll.
- [ ] Both ordering (`After=`) and dependency (`Requires=`/`Wants=`) set where needed.
- [ ] Any wait checks the *right* condition and **fails** on timeout.
- [ ] Every command exists at runtime (`runtimeInputs`/absolute paths).
- [ ] Failure is visible (non-zero exit → `Restart=` → clear log).
- [ ] If it can hang while "running", a watchdog fed by a real probe exists.
- [ ] Resources isolated (own runtime dir / private bus / `RuntimeDirectory=`).
- [ ] New files staged (`git add`) so flakes see them.

## Worked examples from this repo
- **`remote-session`** (headless sway + wayvnc): wayvnc is gated by an
  `ExecStartPre` poll (`waitForSocket`) — rung 5. It works, but the compositor
  could be `Type=notify` instead.
- **`sunshine`** (spike): compositor is `Type=notify` — its wrapper runs sway as a
  child, waits until the Wayland socket is *listening*, `systemd-notify --ready`,
  then `wait`s. The dependent uses only `After=` + `Requires=`, no polling.
- **The `dbus-daemon` `status=127`**: a unit running `sway` crash-looped because
  the wrapper's `dbus-run-session` fallback couldn't find `dbus-daemon`; fix was
  `pkgs.dbus` in `runtimeInputs`.
