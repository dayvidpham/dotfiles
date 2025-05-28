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

  xwayland-satellite_service = (target: {
    Unit = {
      Description = "Standalone rootless Xwayland compositor running in Wayland";
      BindsTo = target;
      PartOf = target;
      After = target;
      Requisite = target;
    };
    Service = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = "${cfg.package}/bin/xwayland-satellite";
      StandardOutput = "journal";
    };
    Install = {
      WantedBy = [ target ];
    };
  });

  xwayland-satellite-ready_sh = pkgs.writeShellApplication {
    name = "xwayland-satellite-ready";
    runtimeInputs = [ pkgs.dbus pkgs.systemd ];
    text = ''
      #!/usr/bin/env sh

      XWAYLAND_SATELLITE_START_TIME="$(systemctl --user show xwayland-satellite.service --property=ExecMainStartTimestamp --value)"
      JOURNAL_OUTPUT="$(journalctl --user -u xwayland-satellite.service --since="$XWAYLAND_SATELLITE_START_TIME" -o "cat")"

      # Parse from journalctl
      JOURNAL_DISPLAY_LINE=$(echo "$JOURNAL_OUTPUT" | grep -o 'Connected to Xwayland on :[[:alnum:]]*')
      DISPLAY="$(expr "$JOURNAL_DISPLAY_LINE" : '.*\(:[0-9.]*\)$' )"
      export DISPLAY

      echo "[INFO] Extracted this line from journalctl: '$JOURNAL_DISPLAY_LINE'"
      echo "[INFO] Extracted variable DISPLAY='$DISPLAY' from the above line"

      dbus-update-activation-environment --verbose --systemd DBUS_SESSION_BUS_ADDRESS DISPLAY
    '';
  };

  xwayland-satellite-ready_service = (target: {
    Unit = {
      Description = "Exports the DBUS_SESSION_BUS_ADDRESS, DISPLAY variables";
      BindsTo = target;
      PartOf = target;
      After = target;
      Requisite = target;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${xwayland-satellite-ready_sh}/bin/${xwayland-satellite-ready_sh.name}";
      StandardOutput = "journal";
    };
    Install = {
      WantedBy = [ target ];
    };
  });

in
{
  options.CUSTOM.services.xwayland-satellite = {
    enable = mkEnableOption "enable xwayland-satellite";
    package = mkPackageOption pkgs "xwayland-satellite" { };
    systemd.enable = mkOption {
      type = lib.types.bool;
      default = true;
      description = "enable the systemd 'xwayland-satellite.service' to launch on start";
      example = "true";
    };
    systemd.target = mkOption {
      type = lib.types.str;
      default = "graphical-session-pre.target";
      description = "systemd desktop unit dependency";
      example = "graphical-session-pre.target";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      cfg.package
    ];

    systemd.user.services = {
      xwayland-satellite = mkIf cfg.systemd.enable (xwayland-satellite_service cfg.systemd.target);
      xwayland-satellite-ready = mkIf cfg.systemd.enable (xwayland-satellite-ready_service "xwayland-satellite.service");
    };
  };
}
