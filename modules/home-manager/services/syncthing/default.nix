{ config, pkgs, lib ? config.lib, ... }:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    ;

  # Replace with the actual Headscale IPs of your other devices
  desktopIp = "100.64.0.3";
  flowx13Ip = "100.64.0.6";

  cfg = config.CUSTOM.services.syncthing;
in
{
  options.CUSTOM.services.syncthing = {
    enable = mkEnableOption "runs syncthing service to track Zotero library";
  };

  config = mkIf (cfg.enable) {
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
                keep = 5;
              };
            };
          };
        };
      };
    };

  };
}
