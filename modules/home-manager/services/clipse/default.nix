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
    #   - `wl-paste --watch` is a C wl-clipboard feature; wl-clipboard-rs does
    #     not have it, so pin the C binary by absolute path rather than trusting
    #     whatever `wl-paste` PATH resolves to.
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
