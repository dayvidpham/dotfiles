# Beads — issue tracker designed for AI-supervised coding workflows
#
# Enabling this module installs the `bd` CLI (wrapped with dolt in PATH)
# and starts the dolt-server systemd service.
#
# Federation (Dolt remote push/pull) is opt-in via the `federation` options.
# Per-repo remote URLs are configured in each repo's `.beads/config.yaml`
# (via `bd dolt set federation.remote <url>`); the credentials below are
# user-level and apply to all repos.
#
# Secrets: Uses sops-nix to manage Hosted Dolt credentials. The password
# is never written to the Nix store — only to the sops-managed path,
# then loaded into DOLT_REMOTE_PASSWORD at shell init.
{ config
, pkgs
, lib
, sops-nix ? null
, ...
}:
let
  cfg = config.CUSTOM.programs.beads;
  fedCfg = cfg.federation;
  secretsCfg = fedCfg.secrets;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkMerge
    optionals
    types
    ;
in
{
  imports = lib.flatten [
    (optionals (sops-nix != null) [
      sops-nix.homeManagerModules.sops
    ])
  ];

  options.CUSTOM.programs.beads = {
    enable = mkEnableOption "beads issue tracker with Dolt backend";

    federation = {
      remoteUser = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Hosted Dolt remote user for push/pull authentication.
          Sets the DOLT_REMOTE_USER environment variable.
        '';
      };

      secrets = {
        enable = mkEnableOption "sops-nix managed credentials for Dolt federation";

        sopsFile = mkOption {
          type = types.path;
          description = "Path to the sops-encrypted secrets file containing the Dolt remote password";
          example = ./secrets/dolt.yaml;
        };

        remotePasswordKey = mkOption {
          type = types.str;
          default = "dolt_remote_password";
          description = "Key in the sops file for the Dolt remote password";
        };
      };

      remotePasswordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to a file containing the Hosted Dolt remote password.
          Prefer federation.secrets for sops-nix integration; this option
          is for manual/non-sops setups.
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Assertions — always evaluated when beads is enabled
    {
      assertions = [
        {
          assertion = !(secretsCfg.enable && sops-nix == null);
          message = ''
            CUSTOM.programs.beads.federation.secrets.enable requires sops-nix
            to be passed via extraSpecialArgs.
          '';
        }
        {
          assertion = !(fedCfg.remotePasswordFile != null && secretsCfg.enable);
          message = ''
            CUSTOM.programs.beads.federation.remotePasswordFile and
            federation.secrets.enable are mutually exclusive. Use one or the other.
          '';
        }
      ];
    }

    # Base: install beads + enable dolt-server
    {
      home.packages = [ pkgs.beads ];
      CUSTOM.services.dolt-server.enable = true;
    }

    # Federation remote user (plain env var — not a secret)
    (mkIf (fedCfg.remoteUser != null) {
      home.sessionVariables.DOLT_REMOTE_USER = fedCfg.remoteUser;
    })

    # Federation secrets via sops-nix
    (mkIf secretsCfg.enable {
      sops.secrets."dolt/dolt_remote_password" = {
        sopsFile = secretsCfg.sopsFile;
        key = secretsCfg.remotePasswordKey;
      };

      programs.zsh.initExtra = ''
        if [[ -r "${config.sops.secrets."dolt/dolt_remote_password".path}" ]]; then
          export DOLT_REMOTE_PASSWORD="$(< "${config.sops.secrets."dolt/dolt_remote_password".path}")"
        fi
      '';
    })

    # Manual password file (non-sops fallback)
    (mkIf (fedCfg.remotePasswordFile != null && !secretsCfg.enable) {
      programs.zsh.initExtra = ''
        if [[ -r "${toString fedCfg.remotePasswordFile}" ]]; then
          export DOLT_REMOTE_PASSWORD="$(< "${toString fedCfg.remotePasswordFile}")"
        fi
      '';
    })
  ]);
}
