{ config
, pkgs
, lib ? pkgs.lib
, GLOBALS
, ...
}:
let
  cfg = config.CUSTOM.services.xwayland-satellite;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    mkPackageOption
    mkDefaultOption
    mkMerge
    types
    getExe
    ;

  inherit (config.lib.file)
    mkOutOfStoreSymlink
    ;

  inherit (builtins)
    hasAttr
    ;
in
{
  options.CUSTOM.services.xwayland-satellite = {
    enable = mkEnableOption "enable xwayland-satellite";
    package = mkPackageOption pkgs "xwayland-satellite" { };
    systemd.enable = mkEnableOption "enable as systemd service";
    systemd.target = mkOption {
      type = lib.types.str;
      default = config.wayland.systemd.target;
      description = "systemd desktop unit dependency";
      example = "graphical-session.target";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
    ];

    systemd.user.services.xwayland-satellite = mkIf cfg.systemd.enable {
      Unit = {
        Description = "Standalone rootless Xwayland compositor running in Wayland";
        BindsTo = cfg.systemd.target;
        PartOf = cfg.systemd.target;
        After = cfg.systemd.target;
        Requisite = cfg.systemd.target;
      };
      Service = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${cfg.package}/bin/xwayland-satellite";
        StandardOutput = "journal";
      };
      Install = {
        WantedBy = cfg.systemd.target;
      };
    };
  };
}
