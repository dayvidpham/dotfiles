{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.programs.dictate;
in
{
  options.CUSTOM.programs.dictate = {
    enable = lib.mkEnableOption "push-to-talk dictation with Whistle";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # `dictate` toggles a recording and copies the transcript; `dictate-status`
      # feeds the waybar indicator. Both expect the Whistle engine and model in
      # ~/.local/share/whistle, and jq/wl-clipboard/pw-record on PATH.
      (pkgs.writeScriptBin "dictate" (builtins.readFile ./dictate.sh))
      (pkgs.writeScriptBin "dictate-status" (builtins.readFile ./dictate-status.sh))
    ];
  };
}
