# SPIKE (plabs-crh): Sunshine on a dedicated headless compositor, rendered and
# hard-encoded on the RTX 4090 (NVENC).
#
# Why this exists: wayvnc/neatvnc can only hardware-encode via VA-API, and
# nvidia-vaapi-driver is decode-only, so the 4090 cannot H.264-encode with the
# remote-session stack. Sunshine encodes with NVENC directly.
#
# This is additive: it does NOT touch CUSTOM.services.remote-session.
#
# Shape: a second, bare, headless sway compositor renders on the 4090's render
# node; Sunshine captures it with `capture = wlr` (wlr-screencopy, which handles
# virtual/headless outputs) and encodes with NVENC. Nothing here claims a DRM
# card (niri owns card0/card1), so it cannot fight the physical desktop.
#
# KNOWN UNKNOWNS (what the spike is for):
#   - input injection: Sunshine uses uinput; the compositor is started with
#     WLR_LIBINPUT_NO_DEVICES=1 for now, so it cannot yet receive that input.
#     Getting libinput + /dev/input access in a seatless system service is the
#     next iteration.
#   - adapter_name format for NVENC (render node path vs GPU index).
#   - capture = wlr only works if Sunshine is in the same WAYLAND_DISPLAY.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.CUSTOM.services.sunshine;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    ;

  # nixpkgs' sunshine is built with SUNSHINE_ENABLE_CUDA=OFF by default, which
  # silently disables NVENC — it surfaces as "Couldn't scale frame: Invalid
  # argument" and then falls back to software. Rebuild it with CUDA so
  # h264_nvenc is actually functional.
  sunshinePkg = pkgs.sunshine.override {
    cudaSupport = true;
    cudaPackages = pkgs.cudaPackages;
  };

  # Bare headless compositor config. No session-management execs: this must not
  # hijack the host's systemd user manager.
  swayConfig = pkgs.writeText "sunshine-sway.conf" ''
    input "*" {
      xkb_layout us
    }
  '';

  compositor = pkgs.writeShellApplication {
    name = "sunshine-compositor";
    # dbus is required: the nixpkgs sway wrapper falls back to running under
    # `dbus-run-session`, which execs `dbus-daemon` by name and needs it on PATH.
    runtimeInputs = [ pkgs.coreutils pkgs.iproute2 pkgs.gnugrep pkgs.sway pkgs.dbus ];
    text = ''
      set -eu
      mkdir -p ${cfg.runtimeDir}
      # Clear sockets left by a previous crash so the socket name stays stable.
      for s in "${cfg.runtimeDir}"/wayland-* "${cfg.runtimeDir}"/sway-ipc.*.sock; do
        case "$s" in *.lock) continue ;; esac
        [ -S "$s" ] || continue
        ss -xl 2>/dev/null | grep -qF " $s" || rm -f "$s" "$s.lock"
      done
      sway --unsupported-gpu -c ${swayConfig} &
      sway_pid=$!
      trap 'kill "$sway_pid" 2>/dev/null || true' TERM INT

      # sway has no sd_notify support, so run it as a child and report readiness
      # ourselves once its Wayland socket is genuinely listening. The unit is
      # Type=notify, so anything ordered After= it starts only when ready.
      sock="${cfg.runtimeDir}/${cfg.display}"
      ready=0
      for _ in $(seq 1 300); do
        kill -0 "$sway_pid" 2>/dev/null || { echo "compositor exited before becoming ready" >&2; exit 1; }
        if [ -S "$sock" ] && ss -xl 2>/dev/null | grep -qF " $sock"; then
          ready=1
          break
        fi
        sleep 0.1
      done
      if [ "$ready" -ne 1 ]; then
        echo "compositor: wayland socket $sock never became ready" >&2
        exit 1
      fi

      ${config.systemd.package}/bin/systemd-notify --ready
      wait "$sway_pid"
    '';
  };

  sunshineConfig = pkgs.writeText "sunshine-spike.conf" ''
    capture = wlr
    encoder = nvenc
    adapter_name = /dev/dri/renderD128
    output_name = HEADLESS-1
    port = ${toString cfg.port}
    min_log_level = info
    system_tray = disabled
  '';

  # Sunshine needs a writable config dir for its pairing credentials; the
  # settings file itself lives in the store, so pass it explicitly (like the
  # upstream module does).
  sunshine = pkgs.writeShellApplication {
    name = "sunshine-spike";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      mkdir -p "$HOME/.config/sunshine"
      exec ${getExe sunshinePkg} ${sunshineConfig}
    '';
  };
in
{
  options.CUSTOM.services.sunshine = {
    enable = mkEnableOption "Sunshine headless stream on a dedicated compositor (SPIKE)";

    user = mkOption {
      type = types.str;
      default = "minttea";
      description = "User that owns the session";
    };

    runtimeDir = mkOption {
      type = types.str;
      default = "/run/user/1000/sunshine";
      description = "Dedicated XDG_RUNTIME_DIR for this session (keeps its socket separate from the login and remote sessions)";
    };

    display = mkOption {
      type = types.str;
      default = "wayland-1";
      description = "WAYLAND_DISPLAY of the headless compositor";
    };

    renderDevice = mkOption {
      type = types.str;
      default = "/dev/dri/by-path/pci-0000:01:00.0-render";
      description = "DRM render node used for rendering; must be the NVIDIA GPU so NVENC can consume its buffers";
      example = "/dev/dri/by-path/pci-0000:01:00.0-render";
    };

    port = mkOption {
      type = types.port;
      default = 47989;
      description = "Sunshine base port";
    };
  };

  config = mkIf cfg.enable {
    # Sunshine creates the virtual mouse/keyboard through uinput; the package
    # ships the matching udev rules.
    hardware.uinput.enable = true;
    services.udev.packages = [ sunshinePkg ];

    # Deliberately no cap_sys_admin security wrapper: it's only needed for KMS
    # capture (we use `capture = wlr`), and a file-capability binary runs in
    # glibc secure-exec mode, which makes the loader ignore LD_LIBRARY_PATH —
    # breaking NVENC's dlopen of libcuda.so.1 / libnvidia-encode.so.1.

    systemd.services.sunshine-compositor = {
      description = "Headless sway compositor for Sunshine (spike)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "user@1000.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        # Readiness = the Wayland socket is listening (signalled by the wrapper).
        Type = "notify";
        NotifyAccess = "all";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = "/home/${cfg.user}";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -m 0700 ${cfg.runtimeDir}";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "HOME=/home/${cfg.user}"
          "WLR_BACKENDS=headless"
          "WLR_RENDERER=gles2"
          "WLR_RENDER_DRM_DEVICE=${cfg.renderDevice}"
          "WLR_RENDERER_ALLOW_SOFTWARE=1"
          "WLR_LIBINPUT_NO_DEVICES=1"
          "XDG_CURRENT_DESKTOP=sway"
          "XDG_SESSION_TYPE=wayland"
        ];
        ExecStart = getExe compositor;
        Restart = "always";
        RestartSec = 2;
      };
    };

    systemd.services.sunshine-spike = {
      description = "Sunshine headless stream (spike)";
      wantedBy = [ "multi-user.target" ];
      after = [ "sunshine-compositor.service" ];
      requires = [ "sunshine-compositor.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        WorkingDirectory = "/home/${cfg.user}";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
          # NVENC runs through CUDA, and ffmpeg dlopen()s libcuda.so.1 /
          # libnvidia-encode.so.1 at runtime. A systemd service has no graphical
          # session env, so point the loader at the driver runpath explicitly.
          "LD_LIBRARY_PATH=/run/opengl-driver/lib"
        ];
        ExecStart = getExe sunshine;
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
