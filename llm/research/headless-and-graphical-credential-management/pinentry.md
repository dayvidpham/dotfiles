# Mixed graphical/headless GnuPG pinentry

## 1. Do established pinentries provide automatic terminal fallback?

### Takeaway
Yes: upstream Qt pinentry already provides GUI/curses switching; a custom password dialog is unnecessary. Its fallback is **environment detection, not recovery from an unreachable compositor**. [Upstream README](https://github.com/gpg/pinentry/blob/master/README)

### Cited Findings
- **Qt, verified at release 1.3.2:** with `FALLBACK_CURSES`, Linux selects GUI if *any* of these hold: `WAYLAND_DISPLAY` is set (even empty), `XDG_SESSION_TYPE=wayland`, `pinentry_have_display(...)`, or `XDG_SESSION_TYPE=x11`. Otherwise it installs `curses_cmd_handler`. The GUI branch constructs `QApplication`; there is no subsequent curses retry on graphical initialization failure. Stale display/session hints therefore defeat fallback. [Qt release source](https://github.com/gpg/pinentry/blob/pinentry-1.3.2/qt/main.cpp)
- `pinentry_have_display` only tests nonempty `DISPLAY` or a `--display` argument; it does not connect to a server. [Shared upstream implementation](https://github.com/gpg/pinentry/blob/master/pinentry/pinentry.c)
- **GTK2:** with curses fallback compiled, it first requires that display test, then calls `gtk_init_check`; unsuccessful GTK initialization selects curses. Thus it handles a stale/unreachable X display better than Qt's environment-only gate. `WAYLAND_DISPLAY` alone does not pass its initial gate. This is not a native-Wayland replacement for the requested Qt frontend. [GTK2 implementation](https://github.com/gpg/pinentry/blob/master/gtk%2B-2/pinentry-gtk-2.c)
- **GNOME3:** falls back when `DBUS_SESSION_BUS_ADDRESS` is absent, a test Gcr system prompt cannot open, or the GNOME screensaver reports locked. It does **not** simply test `DISPLAY`. “Prompt already in progress” counts as available. Later prompt-creation failure returns an error rather than retrying curses. A reachable but wrong session bus can therefore remain a routing problem. [GNOME3 implementation](https://github.com/gpg/pinentry/blob/master/gnome3/pinentry-gnome3.c)
- Nixpkgs master inspected here packages pinentry 1.3.2; `pinentry-qt` includes Qt6 Wayland, curses and tty builds, with ncurses supplied through the curses flavor. Upstream automatically detects curses fallback. Verify the user's locked nixpkgs rather than assuming master matches it. [Nixpkgs packaging](https://github.com/NixOS/nixpkgs/blob/master/pkgs/tools/security/pinentry/default.nix); [build documentation](https://github.com/gpg/pinentry/blob/master/README)
- **tty versus curses:** tty is upstream's simple terminal frontend without curses dependencies; curses provides a terminal dialog, colors and terminal-capability integration. Tty still needs a usable terminal: its handler opens the supplied tty name and configures terminal attributes. It cannot manufacture interactivity for a background SSH-agent request. [README](https://github.com/gpg/pinentry/blob/master/README); [tty handler](https://github.com/gpg/pinentry/blob/master/tty/pinentry-tty.c)

### Inferences
- Qt plus its built-in curses fallback is the appropriate baseline. Headless **Sway with a connected viewer is still graphical**; a bare SSH shell without display access is the terminal case. Correct routing matters more than physical versus virtual display.
- “Qt always recovers to curses when GUI is broken” would be incorrect.

### Gaps
- These are source-level findings, not interactive tests of this machine. GTK2/GNOME3 observations use upstream master; Qt's crucial gate was also verified against 1.3.2. No user-count/adoption measurements were obtained; upstream inclusion and distribution packaging establish maturity, not popularity.

## 2. What limits shared-agent routing across niri, private Sway and tmux?

### Takeaway
`GPG_TTY` supplies terminal identity; it does not force a graphical pinentry into terminal mode. SSH-agent requests lack display/TTY metadata, so one shared agent cannot automatically identify which concurrent desktop should receive each SSH prompt. [Agent manual](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)

### Cited Findings
- GnuPG explicitly requires `GPG_TTY` to reflect the current `tty`. Its documented shell initialization is `GPG_TTY=$(tty); export GPG_TTY`. [Invocation manual](https://www.gnupg.org/documentation/manuals/gnupg/Invoking-GPG_002dAGENT.html)
- SSH uses the startup terminal/display because its protocol cannot convey those values. The documented switch is `gpg-connect-agent updatestartuptty /bye`. Despite the name, upstream implementation replaces the startup environment with the calling connection's standard session variables. [Agent options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html); [UPDATESTARTUPTTY implementation](https://github.com/gpg/gnupg/blob/master/agent/command.c)
- `keep-tty` and `keep-display` intentionally ignore changes and lock prompting to the original terminal/display. [Agent options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- Current standard environment forwarding includes `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE`, `QT_QPA_PLATFORM`, and `DBUS_SESSION_BUS_ADDRESS`, but **not `XDG_RUNTIME_DIR`**. Pinentry child setup updates listed variables when values exist; it is not a wholesale replacement of the agent's inherited environment. [Session-variable list](https://github.com/gpg/gnupg/blob/master/common/session-env.c); [child setup](https://github.com/gpg/gnupg/blob/master/agent/call-pinentry.c)

### Inferences
- For private-runtime Sway, do not assume exporting `WAYLAND_DISPLAY=wayland-1` in a client also transports its runtime directory. Audit the agent-to-pinentry environment boundary; the correct bus, display socket and runtime directory must belong to the same session.
- Persistent tmux shells can retain obsolete graphical variables or old terminal identity. Refresh the relevant shell/client environment and current `GPG_TTY`; merely updating tmux's server environment does not rewrite an existing shell's environment.
- Updating the shared SSH startup context is a **global, last-update-wins policy**, not per-request routing. Choose a designated prompt session or explicit session switching; genuinely simultaneous independent routing requires architectural separation, not a smarter checkbox.

### Gaps
- No local configuration, agent environment, sockets or credentials were inspected. Exact behavior depends on the user's GnuPG version and service environment.

## 3. What should replace custom switching/remember-password code?

### Takeaway
Prefer packaged Qt pinentry, upstream curses fallback and agent cache TTLs. Keep custom code, if necessary, narrowly about session routing/popup presentation—not collecting or remembering passwords. [README](https://github.com/gpg/pinentry/blob/master/README); [agent cache options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)

### Cited Findings
- Agent memory caching already has idle TTLs: 600 seconds normally, 1800 for SSH; both maximum lifetimes default to 7200 seconds. Access resets the idle timer, not the maximum lifetime. No pinentry “remember” checkbox is required. [Agent options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)
- External caching is separate: GTK2/GNOME3 expose password-manager choices when libsecret support, agent permission and key identity permit it; Qt also has password-manager checkbox text. The common handler saves externally only when permitted and selected. `no-allow-external-cache` disables this integration, **not** the agent's memory TTL cache. External persistence/lifetime belongs to the password-manager backend. [Pinentry common handler](https://github.com/gpg/pinentry/blob/master/pinentry/pinentry.c); [agent options](https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html)

### Inferences
- Recommended sequence: establish Qt/curses behavior; fix per-session environment propagation; explicitly choose shared SSH prompt ownership; only then retain a minimal tmux popup adapter if desired. Existing always-curses wrapper policy prevents Qt being the default.
- Rofi/custom-selector frontends are not needed for this Qt requirement and cannot repair missing SSH request metadata. Loopback is not the recommended interactive fallback; use actual terminal pinentry.

### Gaps
- No third-party wrapper was established as a drop-in solution for this exact private-bus/private-runtime topology. Upstream switching is established; reliable multi-session routing still needs an explicit policy and local validation.
