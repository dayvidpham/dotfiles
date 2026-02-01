# OpenClaw NixOS Module
# Secure personal AI assistant running in isolated Podman containers
#
# This module provides:
# - Rootless Podman containers for OpenClaw instances
# - sops-nix encrypted secrets management
# - Strict network allowlist (Anthropic API only)
# - Inter-instance communication with authenticated RPC
# - Shared context store with gatekeeper
#
# Security Features:
# - Read-only root filesystem
# - No capabilities (CAP_DROP ALL)
# - Seccomp profile enforcement
# - Isolated workspaces per instance
# - No external network access except allowlisted hosts
# - All secrets on tmpfs (never touch disk)
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.openclaw;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    ;

in
{
  imports = [
    ./secrets.nix
    ./container.nix
    ./network.nix
    ./instance.nix
    ./bridge.nix
    # Zero-trust infrastructure (optional)
    ./keycloak.nix
    ./openbao.nix
    ./injector.nix
  ];

  options.CUSTOM.virtualisation.openclaw = {
    enable = mkEnableOption "OpenClaw secure AI assistant containers";

    warnIfSecretsDisabled = mkOption {
      type = lib.types.bool;
      default = true;
      description = "Warn if secrets management is not enabled. Set to false for development.";
    };

    # Zero-trust secrets architecture
    zeroTrust = {
      enable = mkEnableOption ''
        Zero-trust secrets architecture using Keycloak + OpenBao.
        When enabled, containers have NO credentials. Secrets are injected
        by an external sidecar that authenticates via OIDC.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Ensure podman is enabled
    virtualisation.podman.enable = true;
    virtualisation.podman.dockerCompat = true;

    # Enable rootless containers
    virtualisation.podman.defaultNetwork.settings = {
      dns_enabled = true;
    };

    # Required for user linger (rootless podman)
    security.polkit.enable = true;

    # Assertions for configuration validation
    assertions = [
      {
        assertion = cfg.instances != { };
        message = "At least one OpenClaw instance must be configured when openclaw is enabled";
      }
      {
        assertion = cfg.secrets.enable -> (config ? sops && config.sops ? secrets);
        message = "sops-nix must be imported when openclaw.secrets.enable is true";
      }
      {
        assertion = cfg.container.registry == "" -> cfg.container.gatewayPackage != null;
        message = "openclaw.container.gatewayPackage must be set when container.registry is empty (using local build)";
      }
    ];

    # Warning about secrets (can be suppressed for development)
    warnings = lib.optional (cfg.warnIfSecretsDisabled && !cfg.secrets.enable) ''
      OpenClaw is running without sops-nix secrets management.
      This is insecure for production use. Enable CUSTOM.virtualisation.openclaw.secrets.enable
      and configure your sops-nix secrets.
      To suppress this warning during development, set CUSTOM.virtualisation.openclaw.warnIfSecretsDisabled = false.
    '';
  };
}
