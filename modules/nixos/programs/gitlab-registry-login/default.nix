{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.gitlab-registry-login;

  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  gitlabRegistryLogin = pkgs.writeShellApplication {
    name = "gitlab-registry-login";
    runtimeInputs = [
      cfg.podmanPackage
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail
      umask 077

      expected_user=${lib.escapeShellArg cfg.user}
      registry=${lib.escapeShellArg cfg.registry}
      username=${lib.escapeShellArg cfg.username}
      secret_file=${lib.escapeShellArg cfg.secretFile}
      auth_rel_path=${lib.escapeShellArg cfg.authFileRelativePath}

      usage() {
        cat <<EOF
      Usage: gitlab-registry-login

      Authenticate Podman and ORAS to $registry as $username using the
      sops-nix decrypted PAT at $secret_file.

      Writes a dedicated auth file (mode 0600) at:
        \$XDG_RUNTIME_DIR/$auth_rel_path

      Examples:
        gitlab-registry-login
        podman login --authfile "\$XDG_RUNTIME_DIR/$auth_rel_path" --get-login $registry
        oras manifest fetch --registry-config "\$XDG_RUNTIME_DIR/$auth_rel_path" $registry/dayvidpham/humanoid/sfurs-runtime:v35d-sif
      EOF
      }

      if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
        usage
        exit 0
      elif [[ $# -gt 0 ]]; then
        echo "gitlab-registry-login: unexpected arguments: $*" >&2
        usage >&2
        exit 2
      fi

      current_user="$(id -un)"
      if [[ "$current_user" != "$expected_user" ]]; then
        echo "gitlab-registry-login: must run as $expected_user (currently $current_user)" >&2
        exit 1
      fi

      uid="$(id -u)"
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
      if [[ ! -d "$runtime_dir" || -L "$runtime_dir" || ! -O "$runtime_dir" || ! -w "$runtime_dir" ]]; then
        echo "gitlab-registry-login: runtime directory is missing or not writable by $expected_user: $runtime_dir" >&2
        exit 1
      fi

      if [[ ! -e "$secret_file" ]]; then
        echo "gitlab-registry-login: secret file not found: $secret_file" >&2
        echo "gitlab-registry-login: create and encrypt secrets/gitlab/secrets.yaml (key: gitlab_registry_pat), stage it with 'git add', and run './switch.sh nixos'." >&2
        exit 1
      fi

      if [[ ! -f "$secret_file" || ! -r "$secret_file" ]]; then
        echo "gitlab-registry-login: secret file is not readable: $secret_file" >&2
        exit 1
      fi

      if [[ ! -s "$secret_file" ]] || ! grep -q '[^[:space:]]' "$secret_file"; then
        echo "gitlab-registry-login: secret file is empty: $secret_file" >&2
        exit 1
      fi

      auth_file="$runtime_dir/$auth_rel_path"
      auth_dir="$(dirname "$auth_file")"
      install -d -m 0700 "$auth_dir"
      if [[ ! -d "$auth_dir" || -L "$auth_dir" || ! -O "$auth_dir" ]]; then
        echo "gitlab-registry-login: auth directory is invalid: $auth_dir" >&2
        exit 1
      fi
      chmod 0700 "$auth_dir"

      tmp_file="$(mktemp "$auth_dir/.auth.json.XXXXXX")"
      cleanup() {
        rm -f "$tmp_file"
      }
      trap cleanup EXIT
      chmod 0600 "$tmp_file"
      printf '{}\n' > "$tmp_file"

      # Isolate from other registry auth files and credential helpers.
      unset REGISTRY_AUTH_FILE DOCKER_CONFIG

      # Pass the PAT directly from file on stdin; never expose it in argv, env, or logs.
      if ! podman login \
        --authfile "$tmp_file" \
        --username "$username" \
        --password-stdin \
        "$registry" < "$secret_file"; then
        echo "gitlab-registry-login: podman login failed for $username at $registry" >&2
        exit 1
      fi

      chmod 0600 "$tmp_file"
      mv -f "$tmp_file" "$auth_file"
      trap - EXIT

      echo "gitlab-registry-login: authfile written to $auth_file"
    '';
  };
in
{
  options.CUSTOM.programs.gitlab-registry-login = {
    enable = mkEnableOption "on-demand GitLab container registry login helper";

    user = mkOption {
      type = types.str;
      default = "minttea";
      description = "Unprivileged user expected to run gitlab-registry-login.";
    };

    registry = mkOption {
      type = types.str;
      default = "registry.gitlab.com";
      description = "GitLab container registry host.";
    };

    username = mkOption {
      type = types.str;
      default = "dayvidpham-agent_bot";
      description = "GitLab registry username associated with the PAT.";
    };

    secretFile = mkOption {
      type = types.str;
      default = "/run/secrets/gitlab/registry-pat";
      description = "Path to the sops-nix decrypted GitLab registry PAT file.";
    };

    authFileRelativePath = mkOption {
      type = types.str;
      default = "gitlab-registry/auth.json";
      description = "Dedicated auth file path relative to XDG_RUNTIME_DIR.";
    };

    podmanPackage = mkOption {
      type = types.package;
      default = config.virtualisation.podman.package;
      defaultText = lib.literalExpression "config.virtualisation.podman.package";
      description = "Podman package invoked by gitlab-registry-login.";
    };

    package = mkOption {
      type = types.package;
      default = gitlabRegistryLogin;
      readOnly = true;
      description = "The generated gitlab-registry-login CLI package.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.podman.enable;
        message = "CUSTOM.programs.gitlab-registry-login requires virtualisation.podman.enable = true.";
      }
    ];

    environment.systemPackages = [ gitlabRegistryLogin ];
  };
}
