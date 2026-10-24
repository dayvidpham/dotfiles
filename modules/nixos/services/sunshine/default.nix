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
  session = config.CUSTOM.services.remote-session;

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
  # (pkgs-unstable: recent Rust for the edition-2024 build.)
  evbridge = pkgs-unstable.callPackage ../../../../packages/evbridge.nix { };

  sunshineConfig = pkgs.writeText "sunshine-spike.conf" ''
    capture = wlr
    encoder = nvenc
    adapter_name = ${session.renderDevice}
    output_name = HEADLESS-1
    port = ${toString cfg.port}
    min_log_level = info
    system_tray = disabled
    # Explicit persistent app/ROC sink. Do not use Sunshine's reserved virtual
    # sink names: Sunshine takes ownership and unloads those after capture.
    audio_sink = ${session.pulseSink}
    # Shared size persists: disconnect must not undo another viewer's mode.
    global_prep_cmd = [{"do":"${getExe setResolution}"}]
  '';

  # Sunshine exports SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS for application prep, so the
  # headless output can match the client exactly. swaymsg needs the compositor
  # socket (which is PID-named), hence the discovery.
  swayMsg = pkgs.writeShellApplication {
    name = "sunshine-swaymsg";
    runtimeInputs = [ pkgs.coreutils pkgs.sway ];
    text = ''
      set -eu
      sock=""
      for s in "$XDG_RUNTIME_DIR"/sway-ipc.*.sock; do
        [ -S "$s" ] && { sock="$s"; break; }
      done
      [ -n "$sock" ] || { echo "sunshine-swaymsg: no shared compositor IPC socket in $XDG_RUNTIME_DIR" >&2; exit 1; }
      SWAYSOCK="$sock" swaymsg "$@"
    '';
  };

  setResolution = pkgs.writeShellApplication {
    name = "sunshine-set-resolution";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -eu
      for value in "''${SUNSHINE_CLIENT_WIDTH}" "''${SUNSHINE_CLIENT_HEIGHT}" "''${SUNSHINE_CLIENT_FPS}"; do
        [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "sunshine: invalid client mode component" >&2; exit 1; }
      done
      ${getExe swayMsg} "output HEADLESS-1 mode ''${SUNSHINE_CLIENT_WIDTH}x''${SUNSHINE_CLIENT_HEIGHT}@''${SUNSHINE_CLIENT_FPS}Hz"
    '';
  };

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
    enable = mkEnableOption "Sunshine NVENC capture of the persistent remote session";

    port = mkOption {
      type = types.port;
      default = 47989;
      description = "Sunshine base port";
    };

  };

  config = mkIf cfg.enable {
    # Expose the actual production config for inspection and lightweight checks.
    system.build.sunshine-session-config = sunshineConfig;
    assertions = [
      { assertion = session.enable; message = "Sunshine requires CUSTOM.services.remote-session.enable"; }
      { assertion = session.renderDevice != null; message = "Sunshine NVENC requires the shared NVIDIA renderDevice"; }
      { assertion = session.pulseSink != null && session.pulseSink != "sink-sunshine-stereo" && session.pulseServer != null;
        message = "Sunshine requires a shared persistent pulseSink (not its reserved sink-sunshine-stereo) and pulseServer"; }
    ];
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

    systemd.services.sunshine-spike = {
      description = "Sunshine headless stream (spike)";
      wantedBy = [ "remote-session-compositor.service" ];
      after = [ "remote-session-compositor.service" ];
      requires = [ "remote-session-compositor.service" ];
      # Restart the spike whenever the compositor restarts. Requires=/After= only
      # propagate stop and start ordering, so without this Sunshine keeps running
      # against the compositor's dead Wayland socket after a crash-restart.
      partOf = [ "remote-session-compositor.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = session.user;
        Group = "users";
        # Create the virtual input devices via /dev/uinput (group "uinput").
        SupplementaryGroups = [ "uinput" ];
        WorkingDirectory = "/home/${session.user}";
        Environment = [
          "XDG_RUNTIME_DIR=${session.runtimeDir}"
          "WAYLAND_DISPLAY=${session.display}"
          "HOME=/home/${session.user}"
          # Reach the desktop PipeWire so Sunshine can capture the shared sink.
          "PULSE_SERVER=${session.pulseServer}"
          # NVENC runs through CUDA, and ffmpeg dlopen()s libcuda.so.1 /
          # libnvidia-encode.so.1 at runtime. A systemd service has no graphical
          # session env, so point the loader at the driver runpath explicitly.
          "LD_LIBRARY_PATH=/run/opengl-driver/lib"
        ];
        # After= is gated by shared compositor notify readiness.
        ExecStart = getExe sunshine;
        Restart = "always";
        RestartSec = 3;
      };
    };

    # Bridges Sunshine's uinput devices into the headless compositor via the wlr
    # virtual-input protocols. Needs the `input` group to read /dev/input/*.
    systemd.services.sunshine-evbridge = {
      description = "Bridge Sunshine's virtual input into the headless compositor (spike)";
      wantedBy = [ "remote-session-compositor.service" ];
      after = [ "remote-session-compositor.service" "sunshine-spike.service" ];
      requires = [ "remote-session-compositor.service" ];
      partOf = [ "remote-session-compositor.service" ];
      startLimitIntervalSec = 0;

      serviceConfig = {
        Type = "simple";
        User = session.user;
        Group = "users";
        SupplementaryGroups = [ "input" ];
        WorkingDirectory = "/home/${session.user}";
        # Ensure the input dir exists before evbridge's startup scan (it errors
        # with ENOENT when missing); udev fills it via the SYMLINK rule.
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/mkdir -p /dev/sunshine-evdev"
        ];
        Environment = [
          "XDG_RUNTIME_DIR=${session.runtimeDir}"
          "WAYLAND_DISPLAY=${session.display}"
          "HOME=/home/${session.user}"
        ];
        # /dev/sunshine-evdev holds only Sunshine's devices (populated by the udev
        # rule above), so evbridge bridges exactly those and not the host's
        # physical input. --phys-filter guards the periodic mknod scan.
        ExecStart = "${getExe evbridge} --wayland-display ${session.display} --input-dir /dev/sunshine-evdev --phys-filter sunshine --log-level info";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
