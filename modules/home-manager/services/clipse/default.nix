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
    getExe
    ;

  # clipse's own Wayland listener: one wl-paste watcher per type, each feeding
  # clipse's --wl-store handler. --wl-store is essential: it sniffs image magic
  # bytes, saves the image to a file, and records that path, so copying an image
  # back out uses `wl-copy -t image/png < file`. The `-a` path instead stores
  # every entry as text with a null file path, so image copy-out replays raw
  # bytes through `wl-copy --` and pastes as mojibake/Unicode.
  #
  # Why C wl-clipboard and not wl-clipboard-rs: `wl-paste --watch` only exists in
  # the C implementation, so pin the binary by absolute path.
  clipseListen = pkgs.writeShellApplication {
    name = "clipse-listen";
    runtimeInputs = [ pkgs.wl-clipboard pkgs.clipse pkgs.coreutils ];
    text = ''
      set -eu
      pids=()
      cleanup() {
        for p in "''${pids[@]}"; do
          kill "$p" 2>/dev/null || true
        done
      }
      trap cleanup EXIT
      trap 'exit 1' HUP INT TERM

      wl-paste --type image/png --watch clipse --wl-store &
      pids+=("$!")
      wl-paste --type text --watch clipse --wl-store &
      pids+=("$!")

      # If either watcher exits (compositor restart, transient error), tear the
      # other down too so systemd can restart the pair cleanly.
      wait -n
    '';
  };
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
    systemd.user.services.clipse = {
      Unit = {
        Description = "clipse clipboard history listener";
        PartOf = [ cfg.systemdTarget ];
        After = [ cfg.systemdTarget ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
        # Retry forever: the session's compositor may come up after us.
        StartLimitIntervalSec = 0;
      };

      Service = {
        ExecStart = "${getExe clipseListen}";
        Restart = "always";
        RestartSec = 3;
      };

      Install.WantedBy = [ cfg.systemdTarget ];
    };
  };
}
