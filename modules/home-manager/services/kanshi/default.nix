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
      default = config.wayland.systemd.target;
      description = "systemd desktop unit dependency";
      example = "config.wayland.systemd.target";
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
          profile.name = "desktop-1-nvidia";
          profile.outputs = [
            # NOTE: Desktop, 3 monitor setup: |V|[ H ]|V|
            {
              # left
              criteria = "GIGA-BYTE TECHNOLOGY CO., LTD. M27Q 21330B007986";
              mode = "2560x1440";
              scale = 1.00;
              position = "0,0";
              adaptiveSync = false;
              transform = "270";
            }
            {
              # center
              criteria = "GIGA-BYTE TECHNOLOGY CO., LTD. M27Q 21330B008006";
              mode = "2560x1440";
              scale = 1.00;
              position = "1440,374";
              adaptiveSync = false;
            }
            {
              # right
              criteria = "GIGA-BYTE TECHNOLOGY CO., LTD. M27Q 21330B007981";
              mode = "2560x1440";
              scale = 1.00;
              position = "4000,0";
              adaptiveSync = false;
              transform = "270";
            }
          ];
        }
        {
          # NOTE: Laptop
          profile.name = "flowX13";
          profile.outputs = [
            {
              criteria = "eDP-1";
              mode = "1920x1200@120.00Hz";
              scale = 1.0;
            }
          ];
        }
      ];

    };

  };
}

