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
# INPUT: Sunshine injects via uinput (kernel devices on seat0), which the host
# desktop (niri) would also receive. Instead of reading them via libinput, we
# let `evbridge` read Sunshine's devices from evdev and re-emit them through the
# compositor's wlr_virtual_pointer / virtual_keyboard protocols — the same path
# wayvnc uses — so no seat is involved and niri never sees the devices.
#
# KNOWN UNKNOWNS:
#   - adapter_name format for NVENC (render node path vs GPU index).
#   - capture = wlr only works if Sunshine is in the same WAYLAND_DISPLAY.
{
  config,
  lib,
  pkgs,
  # nixpkgs-unstable carries the Sunshine build with the GHSA-fp6g-27w5-489j
  # fix (v2026.914.233613+); the main pkgs is still on an affected version.
  pkgs-unstable,
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
  sunshinePkg = pkgs-unstable.sunshine.override {
    cudaSupport = true;
    cudaPackages = pkgs-unstable.cudaPackages;
  };

  # evbridge re-emits Sunshine's uinput devices into the headless compositor via
  # wlr_virtual_pointer / virtual_keyboard (the path wayvnc uses), so the session
  # needs no libinput/seat and the host desktop never sees the devices.
  evbridge = pkgs.callPackage ../../../../packages/evbridge.nix { };

  # Bare headless compositor config. No session-management execs: this must not
  # hijack the host's systemd user manager.
  # The compositor config is generated at runtime from the user's sway config
  # (see the `compositor` wrapper) so the stream is a full interactive session.

  compositor = pkgs.writeShellApplication {
    name = "sunshine-compositor";
    # dbus is required: the nixpkgs sway wrapper falls back to running under
    # `dbus-run-session`, which execs `dbus-daemon` by name and needs it on PATH.
    # swaybg/foot are on PATH for the compositor's `exec` lines.
    runtimeInputs = [ pkgs.coreutils pkgs.iproute2 pkgs.gnugrep pkgs.sway pkgs.dbus pkgs.swaybg ];
    text = ''
      set -eu
      mkdir -p ${cfg.runtimeDir}
      # Clear sockets left by a previous crash so the socket name stays stable.
      for s in "${cfg.runtimeDir}"/wayland-* "${cfg.runtimeDir}"/sway-ipc.*.sock; do
        case "$s" in *.lock) continue ;; esac
        [ -S "$s" ] || continue
        ss -xl 2>/dev/null | grep -qF " $s" || rm -f "$s" "$s.lock"
      done
      # Reuse the user's real sway config so the stream is a full interactive
      # session (keybindings, bar, launchers). Strip the session-management execs
      # that would hijack the host's systemd/D-Bus — same filtering remote-session
      # uses. Input still arrives via evbridge, not libinput.
      src="''${XDG_CONFIG_HOME:-$HOME/.config}/sway/config"
      out="${cfg.runtimeDir}/sunshine-sway.config"
      {
        printf 'output HEADLESS-1 resolution 1920x1080@60Hz\n'
        if [ -f "$src" ]; then
          grep -vE '^[[:space:]]*(exec|exec_always)[[:space:]].*(dbus-update-activation-environment|systemctl --user|polkit-gnome-authentication-agent)' "$src" \
            | sed -E "s#(/bin/ghostty)(['[:space:]\"])#\1 --gtk-single-instance=false\2#g"
        fi
        printf '\nexec swaybg -c "#1a1a2e"\nexec waybar\n'
      } > "$out"

      sway --unsupported-gpu -c "$out" &
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

    # Hide Sunshine's virtual input devices (VID 0xbeef / PID 0xdead) from
    # libinput, so the host desktop (niri) does not also receive Moonlight input.
    # evbridge reads them straight from evdev, so it is unaffected.
    services.udev.extraRules = ''
      # Sunshine's virtual input devices (libvirtualhid: "libvirtualhid Keyboard",
      # "libvirtualhid Mouse", "libvirtualhid Mouse (Absolute)"). Virtual devices
      # carry no ID_VENDOR_ID/ID_MODEL_ID, so match on the device name instead:
      #  - LIBINPUT_IGNORE_DEVICE: keep the host desktop (niri) from receiving them
      #  - SYMLINK into /dev/sunshine-evdev: a filtered input dir for evbridge
      ACTION=="add|change", SUBSYSTEM=="input", KERNEL=="event[0-9]*", ATTRS{name}=="libvirtualhid*", ENV{LIBINPUT_IGNORE_DEVICE}="1", SYMLINK+="sunshine-evdev/%k"
    '';

    # evbridge scans this dir at startup; ensure it exists even before any device
    # appears (udev only creates it alongside a matching device).
    systemd.tmpfiles.rules = [ "d /dev/sunshine-evdev 0755 root root -" ];

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
          # User profile on PATH/DATA_DIRS so exec'd apps (ghostty, waybar,
          # run-cwd, ...) resolve.
          "PATH=/home/${cfg.user}/.nix-profile/bin:/etc/profiles/per-user/${cfg.user}/bin:/run/current-system/sw/bin"
          "XDG_DATA_DIRS=/home/${cfg.user}/.nix-profile/share:/etc/profiles/per-user/${cfg.user}/share:/run/current-system/sw/share"
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
        # Create the virtual input devices via /dev/uinput (group "uinput").
        SupplementaryGroups = [ "uinput" ];
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

    # Bridges Sunshine's uinput devices into the headless compositor via the wlr
    # virtual-input protocols. Needs the `input` group to read /dev/input/*.
    systemd.services.sunshine-evbridge = {
      description = "Bridge Sunshine's virtual input into the headless compositor (spike)";
      wantedBy = [ "multi-user.target" ];
      after = [ "sunshine-compositor.service" "sunshine-spike.service" ];
      requires = [ "sunshine-compositor.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        SupplementaryGroups = [ "input" ];
        WorkingDirectory = "/home/${cfg.user}";
        # Ensure the input dir exists before evbridge's startup scan (it errors
        # with ENOENT when missing); udev fills it via the SYMLINK rule.
        ExecStartPre = "+${pkgs.coreutils}/bin/mkdir -p /dev/sunshine-evdev";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.runtimeDir}"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
        ];
        # /dev/sunshine-evdev holds only Sunshine's devices (populated by the udev
        # rule above), so evbridge bridges exactly those and not the host's
        # physical input. --phys-filter guards the periodic mknod scan.
        ExecStart = "${getExe evbridge} --wayland-display ${cfg.display} --input-dir /dev/sunshine-evdev --phys-filter sunshine --log-level info";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
