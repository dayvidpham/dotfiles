{ pkgs
, desktopConfig
, flowX13Config
}:
let
  inherit (pkgs) lib;

  desktopCfg = desktopConfig.CUSTOM.programs.gitlab-registry-login;
  flowX13Cfg = flowX13Config.CUSTOM.programs.gitlab-registry-login;
  realPkg = desktopCfg.package;

  # Ensure no systemd unit invokes gitlab-registry-login during activation or boot.
  hasSystemdLogin = units:
    lib.any
      (u:
        let
          sc = u.serviceConfig or { };
          execStart = builtins.toString (sc.ExecStart or "");
          script = builtins.toString (u.script or "");
        in
        lib.hasInfix "gitlab-registry-login" execStart || lib.hasInfix "gitlab-registry-login" script
      )
      (builtins.attrValues units);

  # Stub podman binary used to verify CLI invocation, stdin-only secret passing,
  # authfile isolation, permissions, atomic replacement, and no token leakage.
  fakePodman = pkgs.writeShellScriptBin "podman" ''
    set -euo pipefail

    expected_token="$(cat "$FAKE_EXPECTED_TOKEN_FILE")"
    if [[ "''${FAKE_PODMAN_LOG:-}" != "" ]]; then
      printf 'ARGV:%s\n' "$*" >> "$FAKE_PODMAN_LOG"
      printf 'REGISTRY_AUTH_FILE=%s\n' "''${REGISTRY_AUTH_FILE-<unset>}" >> "$FAKE_PODMAN_LOG"
      printf 'DOCKER_CONFIG=%s\n' "''${DOCKER_CONFIG-<unset>}" >> "$FAKE_PODMAN_LOG"
      if env | grep -Fq "$expected_token"; then
        echo "LEAK_IN_ENV" >> "$FAKE_PODMAN_LOG"
        exit 99
      fi
    fi

    if [[ "''${1:-}" != "login" ]]; then
      echo "unexpected podman subcommand: ''${1:-}" >&2
      exit 2
    fi
    shift

    authfile=""
    username=""
    password_stdin=0
    registry=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --authfile)
          authfile="$2"
          shift 2
          ;;
        --username)
          username="$2"
          shift 2
          ;;
        --password-stdin)
          password_stdin=1
          shift
          ;;
        -*)
          echo "unexpected flag: $1" >&2
          exit 2
          ;;
        *)
          registry="$1"
          shift
          ;;
      esac
    done

    if [[ "$password_stdin" -ne 1 ]]; then
      echo "missing --password-stdin" >&2
      exit 2
    fi
    if [[ -z "$authfile" || ! -s "$authfile" ]]; then
      echo "authfile must exist and be initialized JSON" >&2
      exit 2
    fi
    if [[ "$(cat "$authfile")" != "{}" ]]; then
      echo "expected empty JSON object in temp authfile" >&2
      exit 2
    fi

    token="$(cat)"
    if [[ "$token" != "$expected_token" ]]; then
      echo "token mismatch on stdin" >&2
      exit 3
    fi

    if [[ "''${FAKE_PODMAN_FAIL:-0}" == "1" ]]; then
      echo "Error: authenticating creds for \"$registry\": invalid username/password" >&2
      exit 125
    fi

    printf '{"auths":{"%s":{"auth":"stub-for-%s"}}}\n' "$registry" "$username" > "$authfile"
    echo "Login Succeeded!"
  '';

  # Evaluate the real NixOS module with stubbed podman and builder user ("nixbld")
  # so every branch of the generated script is exercised in the Nix build sandbox.
  testEval = lib.evalModules {
    modules = [
      ({ ... }: {
        options = {
          virtualisation.podman = {
            enable = lib.mkEnableOption "podman";
            package = lib.mkOption {
              type = lib.types.package;
              default = fakePodman;
            };
          };
          environment.systemPackages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.attrs;
            default = [ ];
          };
        };
        config = {
          virtualisation.podman.enable = true;
          CUSTOM.programs.gitlab-registry-login = {
            enable = true;
            user = "nixbld";
            secretFile = "/tmp/gitlab-registry-login-test-secret";
            podmanPackage = fakePodman;
          };
        };
      })
      ../modules/nixos/programs/gitlab-registry-login
    ];
    specialArgs = { inherit pkgs; };
  };

  testPkg = testEval.config.CUSTOM.programs.gitlab-registry-login.package;
in
assert lib.assertMsg desktopCfg.enable "desktop must enable CUSTOM.programs.gitlab-registry-login";
assert lib.assertMsg (desktopCfg.user == "minttea") "desktop gitlab-registry-login user must be minttea";
assert lib.assertMsg (desktopCfg.registry == "registry.gitlab.com") "desktop gitlab-registry-login registry must be registry.gitlab.com";
assert lib.assertMsg (desktopCfg.username == "dayvidpham-agent_bot") "desktop gitlab-registry-login username must be dayvidpham-agent_bot";
assert lib.assertMsg (desktopCfg.secretFile == "/run/secrets/gitlab/registry-pat") "desktop gitlab-registry-login secretFile must be /run/secrets/gitlab/registry-pat";
assert lib.assertMsg (desktopCfg.authFileRelativePath == "gitlab-registry/auth.json") "desktop gitlab-registry-login authFileRelativePath must be gitlab-registry/auth.json";
assert lib.assertMsg (builtins.elem realPkg desktopConfig.environment.systemPackages) "desktop must install gitlab-registry-login in environment.systemPackages";
assert lib.assertMsg (!hasSystemdLogin desktopConfig.systemd.services) "desktop must not run gitlab-registry-login in system units";
assert lib.assertMsg (!hasSystemdLogin desktopConfig.systemd.user.services) "desktop must not run gitlab-registry-login in user units";
assert lib.assertMsg (!flowX13Cfg.enable) "flowX13 must not enable CUSTOM.programs.gitlab-registry-login";
assert lib.assertMsg (!(flowX13Config.sops.secrets ? "gitlab/registry-pat")) "flowX13 must not declare sops.secrets.\"gitlab/registry-pat\"";
assert lib.assertMsg (!(builtins.elem realPkg flowX13Config.environment.systemPackages)) "flowX13 must not install gitlab-registry-login";
pkgs.runCommand "gitlab-registry-login-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    set -euo pipefail

    # 1. Verify .sops.yaml has a GitLab-specific rule before the fallback with
    #    desktop + portable user age recipients only (no flowX13).
    python3 - ${../.sops.yaml} <<'PY'
    import pathlib, re, sys

    text = pathlib.Path(sys.argv[1]).read_text()
    rules = re.split(r'(?m)^  - path_regex:\s*', text)[1:]
    parsed = []
    for block in rules:
        lines = block.splitlines()
        regex = lines[0].strip()
        keys = re.findall(r'age1[0-9a-z]+', block)
        parsed.append((regex, keys))

    regexes = [r for r, _ in parsed]
    assert r'secrets/gitlab/.*\.yaml$' in regexes, f"missing gitlab rule in {regexes}"
    assert r'secrets/.*\.yaml$' in regexes, f"missing fallback rule in {regexes}"
    gitlab_idx = regexes.index(r'secrets/gitlab/.*\.yaml$')
    fallback_idx = regexes.index(r'secrets/.*\.yaml$')
    assert gitlab_idx < fallback_idx, "gitlab rule must appear before fallback rule"

    desktop_key = "age1r2ev7w50syd2adu9e0uus4dllfqy9yc0j3w6ezdntjcsqn9gqejs34qxh9"
    user_key = "age1avxj2pmr8s2e4y7ucse6ks5xfwdftu357lec9ty8qvemw68p6epqq3k04y"
    flowx13_key = "age1qceaa6au6jdtzeadyax8gq36tt8krt2age4k97sa298qnae4x4lqzlx3ag"
    gitlab_keys = parsed[gitlab_idx][1]
    assert gitlab_keys == [desktop_key, user_key], f"unexpected gitlab recipients: {gitlab_keys}"
    assert flowx13_key not in gitlab_keys
    PY

    # 2. Verify secrets.yaml.example documents the exact key.
    grep -Fq 'gitlab_registry_humanoid_pat:' ${../secrets/gitlab/secrets.yaml.example}

    # 3. Verify the real desktop package help, argument validation, and user guard.
    test -x ${realPkg}/bin/gitlab-registry-login
    help_out="$(${realPkg}/bin/gitlab-registry-login --help)"
    grep -Fq 'gitlab-registry/auth.json' <<<"$help_out"
    grep -Fq 'registry.gitlab.com' <<<"$help_out"
    grep -Fq 'dayvidpham-agent_bot' <<<"$help_out"

    if ${realPkg}/bin/gitlab-registry-login --unexpected-flag >/dev/null 2>&1; then
      echo "expected unexpected flag to fail" >&2
      exit 1
    fi

    wrong_user_err="$(${realPkg}/bin/gitlab-registry-login 2>&1 || true)"
    grep -Fq 'must run as minttea' <<<"$wrong_user_err"

    # 4. Behavioral tests in headless environment (no GUI, no D-Bus, no GPG).
    export DBUS_SESSION_BUS_ADDRESS=""
    export DISPLAY=""
    export WAYLAND_DISPLAY=""
    export GNUPGHOME="/nonexistent-gnupg"

    work="$(mktemp -d)"
    export XDG_RUNTIME_DIR="$work/runtime"
    mkdir -m 0700 -p "$XDG_RUNTIME_DIR/containers"
    printf '{"auths":{"quay.io":{"auth":"existing-login"}}}\n' > "$XDG_RUNTIME_DIR/containers/auth.json"
    chmod 0600 "$XDG_RUNTIME_DIR/containers/auth.json"

    secret="/tmp/gitlab-registry-login-test-secret"
    rm -f "$secret"

    # 4a. Missing secret reports problem without creating auth file.
    missing_out="$(${testPkg}/bin/gitlab-registry-login 2>&1 || true)"
    grep -Fq 'secret file not found' <<<"$missing_out"
    test ! -e "$XDG_RUNTIME_DIR/gitlab-registry/auth.json"

    # 4b. Empty / whitespace secret fails cleanly.
    printf '   \n' > "$secret"
    chmod 0400 "$secret"
    empty_out="$(${testPkg}/bin/gitlab-registry-login 2>&1 || true)"
    grep -Fq 'secret file is empty' <<<"$empty_out"
    test ! -e "$XDG_RUNTIME_DIR/gitlab-registry/auth.json"

    # 4c. Valid login writes mode 0600 dedicated authfile, leaves other logins untouched,
    #     and never exposes the token in argv, env, stdout, or stderr.
    sentinel_token="glpat-super-secret-sentinel-12345"
    export FAKE_EXPECTED_TOKEN_FILE="$work/expected-token"
    printf '%s' "$sentinel_token" > "$FAKE_EXPECTED_TOKEN_FILE"
    export FAKE_PODMAN_LOG="$work/podman.log"
    export REGISTRY_AUTH_FILE="$XDG_RUNTIME_DIR/containers/auth.json"
    export DOCKER_CONFIG="$work/docker"
    rm -f "$secret"
    printf '%s' "$sentinel_token" > "$secret"
    chmod 0400 "$secret"

    ok_out="$(${testPkg}/bin/gitlab-registry-login 2>&1)"
    if grep -Fq "$sentinel_token" <<<"$ok_out"; then
      echo "token leaked in command output!" >&2
      exit 1
    fi
    if grep -Fq "$sentinel_token" "$FAKE_PODMAN_LOG"; then
      echo "token leaked in podman argv!" >&2
      exit 1
    fi
    if grep -Fq "LEAK_IN_ENV" "$FAKE_PODMAN_LOG"; then
      echo "token leaked in podman env!" >&2
      exit 1
    fi
    grep -Fq 'REGISTRY_AUTH_FILE=<unset>' "$FAKE_PODMAN_LOG"
    grep -Fq 'DOCKER_CONFIG=<unset>' "$FAKE_PODMAN_LOG"
    grep -Fq -- '--username dayvidpham-agent_bot --password-stdin registry.gitlab.com' "$FAKE_PODMAN_LOG"

    auth_file="$XDG_RUNTIME_DIR/gitlab-registry/auth.json"
    test -f "$auth_file"
    test "$(stat -c '%a' "$XDG_RUNTIME_DIR/gitlab-registry")" = "700"
    test "$(stat -c '%a' "$auth_file")" = "600"
    grep -Fq '"registry.gitlab.com"' "$auth_file"
    grep -Fq 'stub-for-dayvidpham-agent_bot' "$auth_file"

    # Existing default podman auth file must be completely untouched.
    grep -Fq '"quay.io"' "$XDG_RUNTIME_DIR/containers/auth.json"
    if grep -Fq 'gitlab.com' "$XDG_RUNTIME_DIR/containers/auth.json"; then
      echo "default podman authfile was modified!" >&2
      exit 1
    fi

    # 4d. Failed podman login reports failure without leaking token, cleans temp files,
    #     and preserves the previous valid authfile.
    prev_auth="$(cat "$auth_file")"
    export FAKE_PODMAN_FAIL=1
    set +e
    fail_out="$(${testPkg}/bin/gitlab-registry-login 2>&1)"
    fail_rc=$?
    set -e
    test "$fail_rc" -ne 0
    grep -Fq 'podman login failed' <<<"$fail_out"
    if grep -Fq "$sentinel_token" <<<"$fail_out"; then
      echo "token leaked on login failure!" >&2
      exit 1
    fi
    test "$(cat "$auth_file")" = "$prev_auth"
    test "$(find "$XDG_RUNTIME_DIR/gitlab-registry" -maxdepth 1 -type f | wc -l)" -eq 1

    rm -f "$secret"
    touch "$out"
  ''
