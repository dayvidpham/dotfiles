# Credentials across simultaneous graphical and terminal sessions

Research: 2026-10-17. Primary authorities: systemd, GnuPG/Pinentry, GNOME, freedesktop specifications; supplemental OpenSSH documentation. Recommendations below are architectural inferences, not verified NixOS configuration.

## 1. What should be shared, and what must remain session-local?

### Takeaway
Share credential backends; keep compositor environments and prompt destinations session-local. A user manager is not a graphical-session manager, and changing its environment cannot select the requesting desktop reliably.

### Cited Findings
- systemd's user manager and its children live outside individual sessions and are shared by all that user's sessions. Standard PAM sessions also share `/run/user/$UID`; session-private files should incorporate a session ID. Thus separate runtime directories here are a deliberate departure from the default model. — [pam_systemd, upstream manual source](https://raw.githubusercontent.com/systemd/systemd/main/man/pam_systemd.xml)
- The manager environment is passed to processes it spawns, combined with per-unit settings. `set-environment`/`import-environment` operate on manager state, not a per-request desktop context. — [systemctl, Environment Commands](https://raw.githubusercontent.com/systemd/systemd/main/man/systemctl.xml)
- Secret Service prompts are displayed **by the service**. `Prompt(window-id)` supplies a window handle, not a terminal, compositor socket, or full caller environment. Its protocol “session” means a client/service exchange bound to a D-Bus connection, not a login desktop. — [Secret Service §§6,9,13](https://specifications.freedesktop.org/secret-service-spec/latest-single/)
- D-Bus well-known names have a primary owner on a particular bus; separate buses have separate name ownership. — [D-Bus specification, Message Bus Names](https://dbus.freedesktop.org/doc/dbus-specification.html)

### Inferences
- Use one selected Secret Service provider on the canonical user bus and one selected SSH agent socket. Do not enable competing Secret Service activation providers, or let gcr-ssh-agent and gpg-agent inconsistently supply `SSH_AUTH_SOCK`. Disabling the former does **not** imply removing GNOME keyring's separate graphical prompter. — [D-Bus](https://dbus.freedesktop.org/doc/dbus-specification.html), [GnuPG SSH support](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- Preserve private compositor buses/runtime directories. Give credential clients explicit access to canonical endpoints: absolute SSH socket paths; a scoped launcher for CLI clients needing the canonical Secret Service bus. A graphical application needing both its private bus and shared secrets needs an explicit bridge/proxy or revised bus topology—not a global export replacing its session bus. Proxies are integration work. — [systemd](https://raw.githubusercontent.com/systemd/systemd/main/man/systemctl.xml), [Secret Service](https://specifications.freedesktop.org/secret-service-spec/latest-single/)
- Fixing `gcr-prompter` with one global `DISPLAY` merely designates one desktop. It does not route simultaneous requests among niri, Sunshine Sway, VNC Sway and tmux. — [systemd](https://raw.githubusercontent.com/systemd/systemd/main/man/systemctl.xml), [Secret Service §9](https://specifications.freedesktop.org/secret-service-spec/latest-single/)

### Gaps
- These sources establish no mature universal broker for this exact topology. Provider-specific bridges, Wayland environment propagation and same-UID isolation guarantees require separate validation.

## 2. Can GnuPG provide Qt-first, terminal fallback and correct routing?

### Takeaway
Qt Pinentry with curses fallback is established functionality. Reliable **simultaneous SSH prompt routing** is a different problem and is not solved by choosing Qt or refreshing startup environment.

### Cited Findings
- GnuPG has connection/session-specific Pinentry environment options. Its manual requires `GPG_TTY` to reflect the current `tty`. — [Agent OPTION](https://www.gnupg.org/documentation/manuals/gnupg/Agent-OPTION.html), [Invoking gpg-agent](https://www.gnupg.org/documentation/manuals/gnupg/Invoking-GPG_002dAGENT.html)
- SSH's agent protocol cannot tell gpg-agent the client's display/terminal. It uses the agent startup destination; `gpg-connect-agent updatestartuptty /bye` changes that destination. `keep-tty`/`keep-display` intentionally prevent destination changes. — [Agent Options, SSH support](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- Qt Pinentry can fall back to curses when built with fallback support. GnuPG supports bounded internal caches and an optional external Pinentry cache; `no-allow-external-cache` asks Pinentry not to use the latter. — [Pinentry README](https://raw.githubusercontent.com/gpg/pinentry/master/README), [Agent Options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)

### Inferences
- Prefer one canonical gpg-agent, Qt Pinentry with verified curses support, current per-pane `GPG_TTY`, and caller-local graphical variables. Clear stale graphical variables for explicitly terminal-only invocations. Do not assume changed tmux attachment updates existing shells. — [GnuPG invocation](https://www.gnupg.org/documentation/manuals/gnupg/Invoking-GPG_002dAGENT.html), [Pinentry](https://raw.githubusercontent.com/gpg/pinentry/master/README)
- `updatestartuptty` is useful sequentially, but simultaneous clients overwrite shared fallback state: last update wins. Robust alternatives are a deliberately designated prompt destination, separately managed per-session agents, or custom routing glue with explicit session identity. Separate agents sacrifice shared cache and require careful socket/key configuration. — [Agent Options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- Make “remember” opt-in and distinguish timed RAM caching from external wallet storage. External caching reintroduces wallet availability/unlock dependencies. — [Agent Options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)

### Gaps
- Qt's exact checkbox and fallback behavior, particularly invalid versus absent Wayland displays, depends on build/version. These docs do not guarantee crash-to-curses recovery or universal graphical-session routing.

## 3. How should boot-started and genuinely remote sessions unlock credentials?

### Takeaway
PAM auto-unlock needs an available login password. Booting a headless compositor or authenticating a streaming connection is not inherently a password-bearing PAM login.

### Cited Findings
- GNOME keyring's PAM module unlocks the login keyring using the password entered during authentication; PAM ordering must preserve access to that authentication token. — [GNOME PAM documentation](https://wiki.gnome.org/Projects/GnomeKeyring/Pam) (retired wiki; historical upstream documentation)
- GnuPG's extra socket supports forwarding to another machine without copying private keys. OpenSSH supports SSH-agent forwarding, but warns that a compromised remote host can request authentication operations through it. — [GnuPG extra-socket](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html), [OpenSSH ssh(1), -A](https://man.openbsd.org/ssh.1#A)

### Inferences
- Practical baseline: password-based PAM unlock when available; otherwise explicit secure unlock of the canonical wallet, with a designated graphical unlock session or provider-specific terminal workflow. Already-unlocked retrieval avoids prompting, but applications must handle relocking. Fully unattended boot requires a deliberate alternative trust/unlock policy—not merely enabling PAM. — [GNOME PAM](https://wiki.gnome.org/Projects/GnomeKeyring/Pam), [Secret Service §8](https://specifications.freedesktop.org/secret-service-spec/latest-single/)
- Forwarding is optional for **distinct machines** and keeps operations at an originating agent. It is unnecessary for same-host compositors and does not invent missing session identity in SSH requests. — [GnuPG](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html), [OpenSSH](https://man.openbsd.org/ssh.1#A)

### Gaps
- No cited standard supplies a universal curses Secret Service unlock prompt. Swapping wallets alone cannot be claimed to solve all routing, PAM and headless-unlock requirements.
