{ config, pkgs, lib ? config.lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    ;

  # Replace with the actual Headscale IPs of your other devices
  desktopIp = "100.64.0.3";
  flowx13Ip = "100.64.0.6";

  cfg = config.CUSTOM.services.syncthing;
  secretsCfg = cfg.secrets;
in
{
  options.CUSTOM.services.syncthing = {
    enable = mkEnableOption "runs syncthing service to track Zotero library";

    secrets = {
      enable = mkEnableOption "stable API key management via systemd credential";

      apiKeyFile = mkOption {
        type = types.path;
        description = "Path to file containing the decrypted Syncthing API key (e.g. from NixOS sops-nix)";
        example = "/run/secrets/syncthing/apikey";
      };
    };
  };

  config = mkIf (cfg.enable) (mkMerge [
    # Base syncthing configuration
    {
      services.syncthing = {
        enable = true;

        settings = {
          # 1. Network Privacy Settings
          # Disable global discovery so we don't announce our IP to the world.
          # Disable relaying to force a direct connection over Headscale.
          options = {
            globalAnnounceEnabled = false;
            localAnnounceEnabled = false; # Won't work over VPN anyway (no broadcast)
            relaysEnabled = false; # Force direct connection
            urAccepted = -1; # Disable usage reporting
          };

          # 2. GUI Settings
          # Bind the GUI to localhost so it's not exposed
          gui = {
            address = "127.0.0.1:8384";
            theme = "default";
          };

          # 3. Device Configuration (Static IPs are CRITICAL here)
          devices = {
            "desktop" = {
              id = "PBNVVR2-AC7HNJ2-ZNSWJOH-N33ZXDL-4PLSE2K-3KF2TUT-36AVMYK-6PTXRQZ";
              # Hardcode the Headscale IP. Port 22000 is standard.
              addresses = [ "quic://${desktopIp}:22000" ];
            };
            "flowX13" = {
              id = "RS4XGM6-YFBMSFV-MWJJVZP-QXYM7UN-SOT7PKK-4PPDR4L-XMIE6EJ-5JEZOAR";
              addresses = [ "quic://${flowx13Ip}:22000" ];
            };
          };

          # 4. Folder Configuration
          folders = {
            "zotero-storage" = {
              path = "${config.home.homeDirectory}/Zotero/storage";
              id = "zotero-storage-sync";
              label = "Zotero Storage";
              devices = [ "desktop" "flowX13" ];
              versioning = {
                type = "simple";
                params = {
                  keep = "5";
                };
              };
            };
          };
        };
      };
    }

    # Stable API key via STGUIAPIKEY env var (only when secrets.enable = true)
    (mkIf secretsCfg.enable {
      # LoadCredential puts the secret at $CREDENTIALS_DIRECTORY/apikey.
      # ExecStartPre writes it to a tmpfs env file in RuntimeDirectory;
      # EnvironmentFile loads it into syncthing's process only.
      # The env file lives in /run/user/<uid>/syncthing/ (RAM, user-only,
      # cleaned up by systemd on service stop).
      systemd.user.services.syncthing.Service = {
        LoadCredential = "apikey:${secretsCfg.apiKeyFile}";
        RuntimeDirectory = "syncthing";
        ExecStartPre = toString (pkgs.writeShellScript "syncthing-load-apikey" ''
          set -euo pipefail
          umask 0177
          echo "STGUIAPIKEY=$(< "$CREDENTIALS_DIRECTORY/apikey")" \
            > "$RUNTIME_DIRECTORY/apikey.env"
        '');
        EnvironmentFile = "-%t/syncthing/apikey.env";
      };
    })
  ]);
}
