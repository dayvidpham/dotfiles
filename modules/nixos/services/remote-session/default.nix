{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.services.remote-session;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    optionalString
    ;

  # A long-lived sway session that persists across viewer disconnects. It runs
  # the user's own sway config minus the session-management execs (those hijack
  # the host's systemd user manager) and with waybar, mirroring what the waypipe
  # wrapper does for ad-hoc sessions.
  #
  # The headless backend is used; with WLR_RENDERER=gles2 + WLR_RENDER_DRM_DEVICE
  # it still advertises zwp_linux_dmabuf_v1, so clients get GPU buffers.
  swayWrapper = pkgs.writeShellApplication {
    name = "remote-session-sway";
    runtimeInputs = [ pkgs.iproute2 pkgs.gnugrep pkgs.coreutils ];
    text = ''
      set -eu
      # Dedicated runtime dir: clear sockets left by a previous crash so the
      # auto-picked compositor socket is always the same name (wayland-1).
      for s in "$XDG_RUNTIME_DIR"/wayland-* "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do
        case "$s" in *.lock) continue ;; esac
        [ -S "$s" ] || continue
        ss -xl 2>/dev/null | grep -qF " $s" || rm -f "$s" "$s.lock"
      done

      src="''${XDG_CONFIG_HOME:-$HOME/.config}/sway/config"
      out="$XDG_RUNTIME_DIR/remote-session-sway.config"
      if [ -f "$src" ]; then
        grep -vE '^[[:space:]]*(exec|exec_always)[[:space:]].*(dbus-update-activation-environment|systemctl --user|polkit-gnome-authentication-agent)' "$src" \
          | sed -E "s#(/bin/ghostty)(['[:space:]\"])#\1 --gtk-single-instance=false\2#g" \
          > "$out"
        printf '\nexec waybar\n' >> "$out"
        ${optionalString (cfg.outputMode != null) ''printf 'output * mode ${cfg.outputMode}\n' >> "$out"''}
        exec ${pkgs.sway}/bin/sway --unsupported-gpu -c "$out"
      fi
      exec ${pkgs.sway}/bin/sway --unsupported-gpu
    '';
  };

  # GPU (gles2 on a DRM render node) when renderDevice is set, else pixman.
  # GPU enables dmabuf so clients can use GL/Vulkan and wayvnc can use its
  # dmabuf path; WLR_RENDERER_ALLOW_SOFTWARE keeps the session usable if EGL
  # fails.
  renderEnv =
    if cfg.renderDevice == null
    then [ "WLR_RENDERER=pixman" ]
    else [
      "WLR_RENDERER=gles2"
      "WLR_RENDER_DRM_DEVICE=${cfg.renderDevice}"
      "WLR_RENDERER_ALLOW_SOFTWARE=1"
    ];

  backendEnv = [ "WLR_BACKENDS=headless" ];

  wayvncConfig = pkgs.writeText "wayvnc-config" ''
    port=${toString cfg.port}
    enable_auth=false
  '';

  # Wait for the compositor's socket to actually be listening. systemd's After=
  # only orders the units; it does not guarantee the socket exists yet, so
  # wayvnc otherwise races the compositor at startup.
  waitForSocket = pkgs.writeShellApplication {
    name = "remote-session-wait-socket";
    runtimeInputs = [ pkgs.iproute2 pkgs.gnugrep pkgs.coreutils ];
    text = ''
      set -eu
      sock="''${1:?socket path required}"
      i=0
      while [ "$i" -lt 300 ]; do
        if [ -S "$sock" ] && ss -xl 2>/dev/null | grep -qF " $sock"; then
          exit 0
        fi
        i=$((i + 1))
        sleep 0.1
      done
      echo "remote-session-wait-socket: timed out waiting for $sock" >&2
      exit 1
    '';
  };

  # clip CLI + peer-sync. Both Python files must share one store directory
  # because clip-sync.py imports clip.py from its own directory.
  clipSources = ../../../../packages/clip;

  clip = pkgs.writeShellApplication {
    name = "clip";
    runtimeInputs = [ pkgs.python3 pkgs.wl-clipboard ];
    text = ''
      exec python3 ${clipSources}/clip.py "$@"
    '';
  };

  clipSync = pkgs.writeShellApplication {
    name = "clip-sync";
    runtimeInputs = [ pkgs.python3 pkgs.wl-clipboard ];
    text = ''
      exec python3 ${clipSources}/clip-sync.py "$@"
    '';
  };

  # Bind the Tailscale interface IPv4 at runtime so the listener only ever
  # exists on the tailnet. Read the address from the interface (no privileges
  # needed) rather than `tailscale ip` (which requires root/operator). If the
  # interface has no address we refuse to start rather than fall back to a
  # loopback or wildcard bind.
  wayvncWrapper = pkgs.writeShellApplication {
    name = "remote-session-vnc";
    runtimeInputs = [ pkgs.iproute2 pkgs.gawk pkgs.coreutils ];
    text = ''
      set -eu
      ${if cfg.tailnetOnly then ''
      addr="$(ip -4 -o addr show dev "${cfg.interfaceName}" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)"
      if [ -z "$addr" ]; then
        echo "remote-session-vnc: no IPv4 on ${cfg.interfaceName}; refusing to bind (tailnet-only)" >&2
        exit 1
      fi
      '' else ''
      addr="${cfg.address}"
      ''}
      exec ${getExe pkgs.wayvnc} -C ${wayvncConfig} -f ${toString cfg.maxFps} ${optionalString cfg.wayvncGpu "-g"} "$addr"
    '';
  };
in
{
  options.CUSTOM.services.remote-session = {
    enable = mkEnableOption "persistent sway session served over VNC (wayvnc)";

    user = mkOption {
      type = types.str;
      description = "User that owns the session";
      example = "minttea";
    };

    runtimeDir = mkOption {
      type = types.str;
      default = "/run/user/1000/remote";
      description = "Dedicated XDG_RUNTIME_DIR for the session (keeps its socket deterministic)";
    };

    display = mkOption {
      type = types.str;
      default = "wayland-1";
      description = "WAYLAND_DISPLAY of the compositor";
    };

    tmuxTmpDir = mkOption {
      type = types.str;
      default = "/run/user/1000";
      description = ''
        TMUX_TMPDIR for the session, so terminals opened in it reach the same
        tmux server as the normal login session (tmux resolves its socket under
        $TMUX_TMPDIR, else /tmp).
      '';
    };

    outputMode = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional forced output mode (e.g. 1920x1080) applied with `output * mode`";
      example = "1920x1080";
    };

    tailnetOnly = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Bind wayvnc to this node's Tailscale IPv4 (resolved at start), so the
        listener only exists on the tailnet. If Tailscale is down the service
        refuses to start. This is the intended mode.
      '';
    };

    address = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = ''
        Explicit bind address, used only when tailnetOnly = false. Loopback only;
        wildcard addresses are rejected so wayvnc is never exposed publicly.
      '';
    };

    interfaceName = mkOption {
      type = types.str;
      default = "tailscale0";
      description = "Tailscale interface whose IPv4 wayvnc binds to when tailnetOnly = true";
    };

    port = mkOption {
      type = types.port;
      default = 5900;
      description = "TCP port wayvnc listens on";
    };

    maxFps = mkOption {
      type = types.int;
      default = 30;
      description = "wayvnc frame-rate limit";
    };

    wayvncGpu = mkOption {
      type = types.bool;
      default = true;
      description = "Pass -g to wayvnc (dmabuf capture / GPU features)";
    };

    renderDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        DRM render node for GPU rendering (e.g. an iGPU's
        /dev/dri/by-path/pci-0000:16:00.0-render). When null, the compositor
        uses the software renderer (pixman).
      '';
      example = "/dev/dri/by-path/pci-0000:16:00.0-render";
    };

    clipboard = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install the `clip` CLI and mirror a peer's clipboard into this
          session's clipboard, so apps in the VNC session can paste what was
          copied on the client machine (including images, which VNC's own
          text-only clipboard cannot carry). The peer socket is provided by the
          client's `remote-desktop` helper over ssh -R.
        '';
      };

      peerSocket = mkOption {
        type = types.str;
        default = "/run/user/1000/clipd.sock";
        description = "Peer clipd socket, provided by the client's ssh RemoteForward";
      };

      interval = mkOption {
        type = types.float;
        default = 1.0;
        description = "Seconds between peer clipboard polls";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        # Never allow a wildcard bind: with tailnetOnly the address is the
        # Tailscale IP; otherwise only loopback is permitted.
        assertion = cfg.tailnetOnly || cfg.address == "127.0.0.1" || cfg.address == "::1";
        message = "CUSTOM.services.remote-session: address must be loopback unless tailnetOnly is enabled";
      }
    ];

    systemd.services.remote-session-compositor = {
      description = "Persistent sway session for ${cfg.user}";
      documentation = [ "man:sway(1)" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "user@1000.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -m 0700 ${cfg.runtimeDir}";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "WLR_LIBINPUT_NO_DEVICES=1"
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
          "HOME=/home/${cfg.user}"
          "TMUX_TMPDIR=${cfg.tmuxTmpDir}"
          # sway's exec'd children (waybar, ghostty, scripts) need the user's
          # profile on PATH; a system service otherwise only sees the system one.
          # Home-manager standalone installs to ~/.nix-profile, not /etc/profiles.
          "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        ] ++ backendEnv ++ renderEnv;
        ExecStart = "${getExe swayWrapper}";
        ExecStop = "-${pkgs.sway}/bin/swaymsg -s ${cfg.runtimeDir}/${cfg.display} exit";
        Restart = "always";
        RestartSec = 2;
      };
    };

    systemd.services.remote-session-vnc = {
      description = "VNC server for the persistent remote session";
      documentation = [ "man:wayvnc(1)" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "remote-session-compositor.service" "tailscaled.service" ];
      requires = [ "remote-session-compositor.service" ];
      wants = [ "tailscaled.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
        ];
        ExecStartPre = "${getExe waitForSocket} ${cfg.runtimeDir}/${cfg.display}";
        ExecStart = "${getExe wayvncWrapper}";
        Restart = "always";
        RestartSec = 3;
      };
    };

    environment.systemPackages = lib.optional cfg.clipboard.enable clip;

    systemd.services.clip-peer-sync = mkIf cfg.clipboard.enable {
      description = "Mirror the peer clipboard into the remote session";
      after = [ "remote-session-compositor.service" ];
      requires = [ "remote-session-compositor.service" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
        ];
        ExecStart = "${getExe clipSync} ${cfg.clipboard.peerSocket} ${toString cfg.clipboard.interval}";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
