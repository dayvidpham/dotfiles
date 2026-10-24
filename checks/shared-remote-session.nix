# Given either capture consumer, it should use the sole compositor's endpoints.
{ pkgs, config, homeConfig ? null }:
let
  inherit (pkgs) lib;
  session = config.CUSTOM.services.remote-session;
  services = config.systemd.services;
  compositor = services.remote-session-compositor;
  consumers = map (name: services.${name}) [
    "remote-session-vnc" "clip-peer-sync" "sunshine-spike" "sunshine-evbridge"
  ];
  owner = "remote-session-compositor.service";
  environment = service: service.serviceConfig.Environment;
  linked = service:
    builtins.elem owner service.wantedBy
    && builtins.elem owner service.partOf
    && builtins.elem owner service.after
    && builtins.elem owner service.requires
    && builtins.elem "XDG_RUNTIME_DIR=${session.runtimeDir}" (environment service)
    && builtins.elem "WAYLAND_DISPLAY=${session.display}" (environment service)
    && service.serviceConfig.User == session.user
    && service.serviceConfig.Restart == "always";
  audio = if homeConfig == null then null else homeConfig.CUSTOM.services.remote-audio;
in
assert session.enable && config.CUSTOM.services.sunshine.enable;
assert !(services ? sunshine-compositor);
assert compositor.serviceConfig.Type == "notify";
assert compositor.serviceConfig.NotifyAccess == "all";
assert compositor.serviceConfig.TimeoutStartSec == 35;
assert compositor.serviceConfig.KillMode == "control-group";
assert compositor.serviceConfig.TimeoutStopSec == 5;
assert !(compositor.serviceConfig ? ExecStop);
assert lib.all linked consumers;
assert session.renderDevice == "/dev/dri/by-path/pci-0000:01:00.0-render";
assert !session.wayvncGpu;
assert session.outputMode == "1920x1080@60Hz";
assert session.pulseSink == "remote_audio";
assert audio == null || (audio.sinkName == session.pulseSink && audio.role == "send");
assert lib.hasInfix ''ENV{LIBINPUT_IGNORE_DEVICE}="1"'' config.services.udev.extraRules;
assert lib.hasInfix ''SYMLINK+="sunshine-evdev/%k"'' config.services.udev.extraRules;
assert builtins.elem "WLR_LIBINPUT_NO_DEVICES=1" (environment compositor);
assert builtins.elem "WLR_BACKENDS=headless" (environment compositor);
assert lib.hasInfix "--input-dir /dev/sunshine-evdev --phys-filter sunshine" services.sunshine-evbridge.serviceConfig.ExecStart;
assert builtins.elem "PULSE_SINK=${session.pulseSink}" (environment compositor);
assert builtins.elem "LD_LIBRARY_PATH=/run/opengl-driver/lib" (environment services.sunshine-spike);
pkgs.runCommand "shared-remote-session" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./shared-remote-session/test-readiness.py} ${../modules/nixos/services/remote-session/readiness.py}
  python3 - ${config.system.build.sunshine-session-config} <<'PY'
  import json, pathlib, sys
  entries = {}
  for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
      if '=' in line and not line.lstrip().startswith('#'):
          key, value = line.split('=', 1)
          entries[key.strip()] = value.strip()
  assert entries['capture'] == 'wlr'
  assert entries['encoder'] == 'nvenc'
  assert entries['adapter_name'] == '${session.renderDevice}'
  assert entries['audio_sink'] == '${session.pulseSink}'
  prep = json.loads(entries['global_prep_cmd'])
  assert len(prep) == 1 and prep[0]['do'] and not prep[0].get('undo')
  assert 'channels' not in entries
  PY
  python3 - ${config.system.build.shared-session-audio}/share/pipewire/pipewire.conf.d/10-remote-audio.conf <<'PY'
  import pathlib, sys
  text = pathlib.Path(sys.argv[1]).read_text()
  assert text.count('node.name = remote_audio') == 1
  assert 'sink-sunshine' not in text
  PY
  # Real generated compositor wrapper is built (including shellcheck), not a mock.
  test -x ${compositor.serviceConfig.ExecStart}
  touch "$out"
''
