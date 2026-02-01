# OpenClaw Secrets Module
# Configures sops-nix secrets for OpenClaw instances
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw;
  secretsCfg = cfg.secrets;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

  # Generate secret definitions for each instance
  mkInstanceSecrets = instanceName: instanceCfg: {
    "openclaw/${instanceName}/api-key" = {
      sopsFile = secretsCfg.sopsFile;
      key = if instanceCfg.secrets.apiKeyPath != null
            then instanceCfg.secrets.apiKeyPath
            else "anthropic_api_key";
      owner = instanceCfg.user;
      group = instanceCfg.group;
      mode = "0400";
    };

    "openclaw/${instanceName}/instance-token" = {
      sopsFile = secretsCfg.sopsFile;
      key = "${instanceName}_instance_token";
      owner = instanceCfg.user;
      group = instanceCfg.group;
      mode = "0400";
    };

    "openclaw/${instanceName}/bridge-signing-key" = {
      sopsFile = secretsCfg.sopsFile;
      key = "${instanceName}_bridge_signing_key";
      owner = instanceCfg.user;
      group = instanceCfg.group;
      mode = "0400";
    };
  };

in
{
  options.CUSTOM.virtualisation.openclaw.secrets = {
    enable = mkEnableOption "sops-nix secrets management for OpenClaw";

    sopsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the sops-encrypted secrets file";
      example = "/etc/nixos/secrets/openclaw/secrets.yaml";
    };

    ageKeyFile = mkOption {
      type = types.path;
      default = "/var/lib/sops-nix/keys.txt";
      description = "Path to the age private key for decryption";
    };
  };

  config = mkIf cfg.enable {
    # Create the bridge group for shared secret access
    users.groups.openclaw-bridge = { };

    # Assertion to ensure sopsFile is set when secrets are enabled
    assertions = [
      {
        assertion = secretsCfg.enable -> secretsCfg.sopsFile != null;
        message = ''
          CUSTOM.virtualisation.openclaw.secrets.enable is true, but sopsFile is not set.
          Set CUSTOM.virtualisation.openclaw.secrets.sopsFile to your encrypted secrets file.
        '';
      }
    ];

    # Configure sops when secrets are enabled
    sops = mkIf (secretsCfg.enable && secretsCfg.sopsFile != null) {
      defaultSopsFile = secretsCfg.sopsFile;
      age.keyFile = secretsCfg.ageKeyFile;

      # Combine bridge secret with all instance secrets
      secrets = {
        # Shared bridge secret (accessible by bridge service)
        "openclaw/bridge-shared-secret" = {
          sopsFile = secretsCfg.sopsFile;
          key = "bridge_shared_secret";
          owner = "root";
          group = "openclaw-bridge";
          mode = "0440";
        };
      } // (builtins.foldl' (acc: name:
        let instanceCfg = cfg.instances.${name};
        in if instanceCfg.enable
           then acc // (mkInstanceSecrets name instanceCfg)
           else acc
      ) { } (builtins.attrNames cfg.instances));
    };
  };
}
