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
    ;

  # A long-lived, headless sway session that persists across viewer
  # disconnects. It runs the user's own sway config minus the session-management
  # execs (those hijack the host's systemd user manager) and with waybar,
  # mirroring what the waypipe wrapper does for ad-hoc sessions.
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
        exec ${pkgs.sway}/bin/sway --unsupported-gpu -c "$out"
      fi
      exec ${pkgs.sway}/bin/sway --unsupported-gpu
    '';
  };

  wayvncConfig = pkgs.writeText "wayvnc-config" ''
    port=${toString cfg.port}
    enable_auth=false
  '';

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
      exec ${getExe pkgs.wayvnc} -C ${wayvncConfig} -f ${toString cfg.maxFps} "$addr"
    '';
  };
in
{
  options.CUSTOM.services.remote-session = {
    enable = mkEnableOption "persistent headless sway session served over VNC (wayvnc)";

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
      description = "WAYLAND_DISPLAY of the headless compositor";
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
  };

  config = mkIf cfg.enable {
    assertions = [{
      # Never allow a wildcard bind: with tailnetOnly the address is the
      # Tailscale IP; otherwise only loopback is permitted.
      assertion = cfg.tailnetOnly || cfg.address == "127.0.0.1" || cfg.address == "::1";
      message = "CUSTOM.services.remote-session: address must be loopback unless tailnetOnly is enabled";
    }];

    systemd.services.remote-session-compositor = {
      description = "Persistent headless sway session for ${cfg.user}";
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
          "WLR_BACKENDS=headless"
          "WLR_RENDERER=pixman"
          "WLR_LIBINPUT_NO_DEVICES=1"
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
          "HOME=/home/${cfg.user}"
          # sway's exec'd children (waybar, ghostty, scripts) need the user's
          # profile on PATH; a system service otherwise only sees the system one.
          "PATH=/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        ];
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
        ExecStart = "${getExe wayvncWrapper}";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
