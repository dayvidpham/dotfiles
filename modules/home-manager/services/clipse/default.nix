{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.clipse;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    ;

in
{
  options.CUSTOM.services.clipse = {
    enable = mkEnableOption "clipse clipboard history listener";

    systemdTarget = mkOption {
      type = types.str;
      default = config.wayland.systemd.target;
      description = "systemd target that provides the graphical session";
      example = "config.wayland.systemd.target";
    };
  };

  config = mkIf cfg.enable {
    # On Wayland, clipse records history by having wl-paste watch the selection
    # and pipe each change into `clipse -a`. Two gotchas this encodes:
    #   - the C wl-clipboard provides `wl-paste --watch`; wl-clipboard-rs does
    #     NOT, and it is the one that shadows wl-paste on PATH, so use the C
    #     binary by absolute path.
    #   - it must run inside the session (WAYLAND_DISPLAY); hence a user unit.
    systemd.user.services.clipse = {
      Unit = {
        Description = "clipse clipboard history listener";
        PartOf = [ cfg.systemdTarget ];
        After = [ cfg.systemdTarget ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Service = {
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.clipse}/bin/clipse -a";
        Restart = "always";
        RestartSec = 3;
      };

      Install.WantedBy = [ cfg.systemdTarget ];
    };
  };
}
