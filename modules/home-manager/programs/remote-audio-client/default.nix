{ config, pkgs, lib, ... }:
let
  cfg = config.CUSTOM.programs.remote-audio-client;
  audio = config.CUSTOM.services.remote-audio;
  receiver = "remote-audio-recv.service";
  scope = "moonlight-client.scope";
  systemctl = "${cfg.systemdPackage}/bin/systemctl";
  moonlight = pkgs.writeShellApplication {
    name = "moonlight-qt";
    text = ''
      export SDL_MOUSE_RELATIVE_SYSTEM_SCALE=1
      if ${cfg.systemdPackage}/bin/systemd-run --user --scope --collect \
        --unit=${scope} --expand-environment=no \
        --property=Conflicts=${receiver} --property=After=${receiver} \
        -- ${lib.getExe cfg.moonlightPackage} "$@"; then
        exit 0
      else
        result=$?
        printf '%s\n' "moonlight-qt: managed launch or client exited with status $result." \
          'If Moonlight is already open, use that window or close it before retrying.' \
          'Inspect: systemctl --user status moonlight-client.scope; unwrapped launches are not audio-managed.' >&2
        exit "$result"
      fi
    '';
  };
  selector = pkgs.writeShellApplication {
    name = "remote-audio-mode";
    text = ''
      usage() {
        printf '%s\n' 'Usage: remote-audio-mode native|vnc|status' \
          'native stops ROC; vnc closes managed Moonlight and starts ROC; status reports actual unit states.' \
          'VNC attachment alone does not select audio. Starting moonlight-qt selects native audio.' >&2
      }
      if [ "$#" -ne 1 ]; then usage; exit 2; fi
      case "$1" in
        native)
          ${systemctl} --user stop ${receiver}
          printf '%s\n' 'Native Moonlight audio selected; ROC is stopped. Launch moonlight-qt when ready.'
          ;;
        vnc)
          printf '%s\n' 'Selecting VNC/ROC audio closes the managed Moonlight client, if open.' \
            'The remote desktop session and its windows remain running. No automatic restore on viewer exit.' >&2
          ${systemctl} --user start ${receiver}
          ;;
        status)
          ${systemctl} --user show ${receiver} ${scope} --property=Id --property=ActiveState --property=SubState
          ;;
        *)
          usage
          exit 2
          ;;
      esac
    '';
  };
in
{
  options.CUSTOM.programs.remote-audio-client = {
    enable = lib.mkEnableOption "exclusive native Moonlight or manually selected VNC/ROC audio";
    moonlightPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.moonlight-qt;
      description = "Original Moonlight package, launched inside the singleton user scope.";
    };
    systemdPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.systemd;
      description = "Package providing systemd-run and systemctl.";
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = audio.enable && audio.role == "recv" && !audio.autostart;
      message = "remote-audio-client requires remote-audio enabled with role=recv and autostart=false (native Moonlight is the login default).";
    }];
    home.packages = [ moonlight selector ];
    # A single ordering edge orders BOTH transitions: the conflicting unit must
    # finish stopping before the other starts. Do not add the reverse After edge.
    systemd.user.services.remote-audio-recv.Unit.Conflicts = [ scope ];
    # Upstream's desktop entry uses 'moonlight', not our 'moonlight-qt' wrapper.
    # Override its desktop ID so the normal graphical launcher is managed too.
    xdg.desktopEntries."com.moonlight_stream.Moonlight" = {
      name = "Moonlight";
      comment = "Stream the remote desktop (native audio; stops VNC/ROC audio)";
      exec = lib.getExe moonlight;
      icon = "${cfg.moonlightPackage}/share/icons/hicolor/scalable/apps/moonlight.svg";
      terminal = false;
      categories = [ "Qt" "Game" ];
    };
  };
}
