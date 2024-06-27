{ config
, pkgs
, lib ? pkgs.lib
, terminal
, menu
, ...
}:
let
  cfg = config.CUSTOM.services.kanshi;

  inherit (lib)
    mkIf
    mkEnableOption
    mkDefault
    mkOption
    ;

in
{
  options.CUSTOM.services.kanshi = {
    enable =
      mkEnableOption "setup Wayland displays to personal preference";
    systemdTarget = mkOption {
      type = lib.types.str;
      default = "graphical-session.target";
      description = "systemd desktop unit dependency";
      example = "graphical-session.target";
    };
  };

  config = mkIf cfg.enable {

    home.packages = [
      pkgs.kanshi
    ];

    # Not enabled by default
    systemd.user.services.kanshi.Unit.X-Restart-Triggers = [
      "${config.xdg.configFile."kanshi/config".source}"
    ];
    services.kanshi = {
      enable = true;
      systemdTarget = cfg.systemdTarget;
      settings = [

        {
          profile.name = "desktop-1";
          profile.outputs = [

            # NOTE: Desktop, 3 monitor setup: |V|[ H ]|V|
            {
              # left
              criteria = "DP-3";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "0,0";
              adaptiveSync = true;
              transform = "270";
            }
            {
              # center
              criteria = "DP-2";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "1152,374";
              adaptiveSync = true;
            }
            {
              # right
              criteria = "DP-1";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "3200,0";
              adaptiveSync = true;
              transform = "270";
            }

          ];
        }

        {
          profile.name = "desktop-2";
          profile.outputs = [

            # NOTE: Desktop, 3 monitor setup: |V|[ H ]|V|
            {
              # left
              criteria = "DP-6";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "0,0";
              adaptiveSync = true;
              transform = "270";
            }
            {
              # center
              criteria = "DP-5";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "1152,374";
              adaptiveSync = true;
            }
            {
              # right
              criteria = "DP-4";
              mode = "2560x1440@169.831Hz";
              scale = 1.25;
              position = "3200,0";
              adaptiveSync = true;
              transform = "270";
            }

          ];
        }

        # NOTE: Laptop
        {
          profile.name = "flowX13";
          profile.outputs = [
            {
              criteria = "eDP-1";
              mode = "1920x1200@119.90Hz";
              scale = 1.25;
            }
          ];
        }
      ];

    };

  };
}

