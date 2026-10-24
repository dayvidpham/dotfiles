{ pkgs, home-manager }:
let
  inherit (pkgs) lib;
  systemd = pkgs.symlinkJoin {
    name = "audio-systemd-fixture";
    paths = [
      (pkgs.writeScriptBin "systemd-run" ''
        #!${pkgs.python3}/bin/python3
        import json, os, sys
        with open(os.environ['RUN_LOG'], 'w') as f: json.dump(sys.argv[1:], f)
        if os.environ.get('RUN_FAILURE'): sys.exit(int(os.environ['RUN_FAILURE']))
        i = sys.argv.index('--')
        os.execv(sys.argv[i+1], sys.argv[i+1:])
      '')
      (pkgs.writeScriptBin "systemctl" ''
        #!${pkgs.python3}/bin/python3
        import json, os, sys
        with open(os.environ['CTL_LOG'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\n')
        sys.exit(int(os.environ.get('CTL_FAILURE', '0')))
      '')
    ];
  };
  moonlight = pkgs.writeScriptBin "moonlight-qt" ''
    #!${pkgs.python3}/bin/python3
    import json, os, sys
    with open(os.environ['APP_LOG'], 'w') as f:
        json.dump({'args':sys.argv[1:], 'env':{k:os.environ.get(k) for k in
                   ['SDL_MOUSE_RELATIVE_SYSTEM_SCALE', 'WAYLAND_DISPLAY', 'DISPLAY',
                    'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'AUDIO_TEST_LITERAL']}}, f)
    sys.exit(int(os.environ.get('APP_FAILURE', '0')))
  '';
  base = {
    imports = [
      ../modules/home-manager/programs/remote-audio-client
      ../modules/home-manager/services/remote-audio
    ];
    home.username = "fixture";
    home.homeDirectory = "/home/fixture";
    home.stateVersion = "25.11";
  };
  evaluate = modules: (home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { pkgs-unstable = pkgs // { moonlight-qt = moonlight; }; };
    modules = [ base ] ++ modules;
  }).config;
  # Import the actual host file, not a separately reimplemented policy fixture.
  client = evaluate [
    ../users/minttea/home.flowX13.nix
    ({ lib, ... }: {
      options.CUSTOM = {
        wayland = lib.mkOption { type = lib.types.attrs; default = {}; };
        services.syncthing = lib.mkOption { type = lib.types.attrs; default = {}; };
        services.clipd = lib.mkOption { type = lib.types.attrs; default = {}; };
        services.clip-tunnel = lib.mkOption { type = lib.types.attrs; default = {}; };
        programs.remote-desktop = lib.mkOption { type = lib.types.attrs; default = {}; };
      };
      config.CUSTOM.programs.remote-audio-client.systemdPackage = systemd;
    })
  ];
  recv = evaluate [{ CUSTOM.services.remote-audio = { enable = true; role = "recv"; }; }];
  send = evaluate [{ CUSTOM.services.remote-audio = { enable = true; role = "send"; }; }];
  packageNamed = name: lib.findFirst (p: lib.getName p == name)
    (throw "missing generated ${name}") client.home.packages;
  wrapper = packageNamed "moonlight-qt";
  selector = packageNamed "remote-audio-mode";
in
assert lib.all (a: a.assertion) client.assertions;
assert client.CUSTOM.services.remote-audio.autostart == false;
assert client.systemd.user.services.remote-audio-recv.Install.WantedBy == [];
assert client.systemd.user.services.remote-audio-recv.Unit.Conflicts == [ "moonlight-client.scope" ];
assert !(builtins.elem "moonlight-client.scope" client.systemd.user.services.remote-audio-recv.Unit.After);
assert recv.systemd.user.services.remote-audio-recv.Install.WantedBy == [ "default.target" ];
assert send.systemd.user.services.remote-audio-send.Install.WantedBy == [ "default.target" ];
assert client.xdg.desktopEntries."com.moonlight_stream.Moonlight".exec == lib.getExe wrapper;
pkgs.runCommand "remote-audio-client-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export WRAPPER=${lib.getExe wrapper}
  export SELECTOR=${lib.getExe selector}
  export APP=${lib.getExe moonlight}
  python3 - <<'PY'
  import json, os, subprocess
  from pathlib import Path
  root = Path(os.environ['TMPDIR'])
  env = dict(os.environ, RUN_LOG=str(root/'run.json'), APP_LOG=str(root/'app.json'),
             CTL_LOG=str(root/'ctl.jsonl'), WAYLAND_DISPLAY='wayland-literal', DISPLAY=':42',
             XDG_RUNTIME_DIR='/run/user/fixture', DBUS_SESSION_BUS_ADDRESS='unix:path=/fixture',
             AUDIO_TEST_LITERAL='$NAME \\ "quoted"')
  wrapper, selector = env['WRAPPER'], env['SELECTOR']
  def invoke(command, args, additions=None, status=0):
      result = subprocess.run([command, *args], env=env | (additions or {}), capture_output=True, text=True)
      assert result.returncode == status, (result.returncode, result.stdout, result.stderr)
      return result
  args = ['stream', 'desktop', 'Remote', '$NAME', '$'+'{NAME}', '"quoted"', r'back\slash', '--leading-argument']
  invoke(wrapper, args)
  run = json.loads((root/'run.json').read_text())
  assert run == ['--user', '--scope', '--collect', '--unit=moonlight-client.scope',
                 '--expand-environment=no', '--property=Conflicts=remote-audio-recv.service',
                 '--property=After=remote-audio-recv.service', '--', env['APP'], *args], run
  app = json.loads((root/'app.json').read_text())
  assert app['args'] == args
  assert app['env']['SDL_MOUSE_RELATIVE_SYSTEM_SCALE'] == '1'
  for k,v in app['env'].items():
      if k != 'SDL_MOUSE_RELATIVE_SYSTEM_SCALE': assert v == env[k], (k,v)
  invoke(wrapper, ['--leading-first', '$NAME'])
  assert json.loads((root/'app.json').read_text())['args'] == ['--leading-first', '$NAME']
  assert not (root/'ctl.jsonl').exists()  # no independent stop/start race in wrapper
  failure = invoke(wrapper, args, {'RUN_FAILURE':'17'}, status=17)
  assert 'already open' in failure.stderr and 'systemctl --user status' in failure.stderr
  invoke(wrapper, args, {'APP_FAILURE':'23'}, status=23)
  assert not (root/'ctl.jsonl').exists()  # no restore even on client failure
  invoke(selector, ['native'])
  warning = invoke(selector, ['vnc'])
  assert 'closes the managed Moonlight client' in warning.stderr
  assert 'windows remain running' in warning.stderr
  invoke(selector, ['status'])
  assert [json.loads(line) for line in (root/'ctl.jsonl').read_text().splitlines()] == [
      ['--user','stop','remote-audio-recv.service'],
      ['--user','start','remote-audio-recv.service'],
      ['--user','show','remote-audio-recv.service','moonlight-client.scope',
       '--property=Id','--property=ActiveState','--property=SubState']]
  invoke(selector, ['vnc'], {'CTL_FAILURE':'7'}, status=7)
  before = (root/'ctl.jsonl').read_text()
  bad = invoke(selector, ['bogus'], status=2)
  assert 'Usage:' in bad.stderr
  assert 'Usage:' in invoke(selector, [], status=2).stderr
  assert 'Usage:' in invoke(selector, ['native','extra'], status=2).stderr
  assert (root/'ctl.jsonl').read_text() == before  # invalid arity cannot switch mode
  PY
  touch "$out"
''
