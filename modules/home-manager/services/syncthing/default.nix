{ config, pkgs, lib ? config.lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkMerge
    types
    getExe
    ;

  # Replace with the actual Headscale IPs of your other devices
  desktopIp = "100.64.0.3";
  flowx13Ip = "100.64.0.6";

  cfg = config.CUSTOM.services.syncthing;
  secretsCfg = cfg.secrets;

  # Script that PATCHes the syncthing API key from a credential file.
  # Reads the current key from config.xml, skips if already matching.
  apikeyScript = pkgs.writeShellScript "syncthing-set-apikey" ''
    set -euo pipefail

    APIKEY=$(< "$CREDENTIALS_DIRECTORY/apikey")
    CONFIG_XML="${config.home.homeDirectory}/.local/state/syncthing/config.xml"

    # Wait for config.xml to exist (syncthing writes it on first start)
    for i in $(seq 1 30); do
      [ -f "$CONFIG_XML" ] && break
      sleep 1
    done

    if [ ! -f "$CONFIG_XML" ]; then
      echo "ERROR: config.xml not found after 30s" >&2
      exit 1
    fi

    # Extract current API key from config.xml
    CURRENT=$(${getExe pkgs.xmlstarlet} sel -t -v "/configuration/gui/apikey" "$CONFIG_XML" 2>/dev/null || echo "")

    if [ "$CURRENT" = "$APIKEY" ]; then
      echo "API key already matches, skipping PATCH"
      exit 0
    fi

    # Extract current API key for auth header (syncthing may have regenerated it)
    if [ -z "$CURRENT" ]; then
      echo "ERROR: could not read current API key from config.xml" >&2
      exit 1
    fi

    # PATCH the stable key via REST API
    ${getExe pkgs.curl} -sf \
      -X PATCH \
      -H "X-API-Key: $CURRENT" \
      -H "Content-Type: application/json" \
      -d "{\"apiKey\": \"$APIKEY\"}" \
      http://127.0.0.1:8384/rest/config/gui

    echo "API key PATCHed successfully"
  '';
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
        tray.enable = true;

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
              addresses = [ "tcp://${desktopIp}:22000" ];
            };
            "flowX13" = {
              id = "RS4XGM6-YFBMSFV-MWJJVZP-QXYM7UN-SOT7PKK-4PPDR4L-XMIE6EJ-5JEZOAR";
              addresses = [ "tcp://${flowx13Ip}:22000" ];
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

    # API key service (only when secrets.enable = true)
    (mkIf secretsCfg.enable {
      systemd.user.services.syncthing-apikey = {
        Unit = {
          Description = "Set stable Syncthing API key";
          After = [ "syncthing-init.service" ];
          Requires = [ "syncthing-init.service" ];
        };

        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          LoadCredential = "apikey:${secretsCfg.apiKeyFile}";
          ExecStart = toString apikeyScript;
        };

        Install = {
          WantedBy = [ "syncthing-init.service" ];
        };
      };
    })
  ]);
}
