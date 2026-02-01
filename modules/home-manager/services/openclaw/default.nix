# OpenClaw Home Manager Service
# Simple wrapper around nix-openclaw's homeManagerModules.openclaw
#
# This provides a CUSTOM.services.openclaw option that enables
# the upstream nix-openclaw module with its sensible defaults.
#
# Security Note: This runs openclaw directly (not containerized).
# See beads task dotfiles-7x5 for planned security hardening.
{ config
, pkgs
, lib
, nix-openclaw ? null
, ...
}:
let
  cfg = config.CUSTOM.services.openclaw;

  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    types
    ;

in
{
  imports = lib.optionals (nix-openclaw != null) [
    nix-openclaw.homeManagerModules.openclaw
  ];

  options.CUSTOM.services.openclaw = {
    enable = mkEnableOption "OpenClaw AI assistant";

    stateDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.openclaw";
      description = "Directory for OpenClaw state and configuration";
    };

    workspaceDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.openclaw/workspace";
      description = "Directory for OpenClaw workspace";
    };

    gatewayPort = mkOption {
      type = types.port;
      default = 18789;
      description = "Port for the OpenClaw gateway";
    };

    documentsPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to directory containing AGENTS.md, SOUL.md, TOOLS.md";
      example = "/home/minttea/.config/openclaw/documents";
    };
  };

  config = mkIf cfg.enable {
    # Assertion: nix-openclaw must be available
    assertions = [
      {
        assertion = nix-openclaw != null;
        message = ''
          CUSTOM.services.openclaw requires nix-openclaw to be passed via extraSpecialArgs.
          Add nix-openclaw to your home-manager configuration's extraSpecialArgs.
        '';
      }
    ];

    # Configure the upstream openclaw module
    # SECURITY: Minimal configuration - localhost webchat only, no external channels
    programs.openclaw = {
      enable = true;
      stateDir = cfg.stateDir;
      workspaceDir = cfg.workspaceDir;
      documents = cfg.documentsPath;

      # No external plugins
      plugins = [ ];

      # SECURITY: Disable ALL first-party plugins
      # These can expose external APIs (web search, screenshots, calendar, etc.)
      firstParty = {
        summarize.enable = false;   # Summarize web pages, PDFs, videos
        peekaboo.enable = false;    # Take screenshots
        oracle.enable = false;      # Web search
        poltergeist.enable = false; # Control your macOS UI
        sag.enable = false;         # Text-to-speech
        camsnap.enable = false;     # Camera snapshots
        gogcli.enable = false;      # Google Calendar
        bird.enable = false;        # Twitter/X
        sonoscli.enable = false;    # Sonos control
        imsg.enable = false;        # iMessage
      };

      # SECURITY: No external channels (telegram, discord, etc.)
      # Gateway provides localhost webchat only
      config = {
        # Explicitly null out channels to prevent any external messaging
        channels = null;
        # Gateway binds to localhost by default
        gateway = {
          # Local mode - no remote connections
          mode = "local";
        };
      };

      # Use default instance with our port
      instances.default = {
        enable = true;
        gatewayPort = cfg.gatewayPort;
        systemd.enable = true;
        systemd.unitName = "openclaw-gateway";
      };
    };
  };
}
