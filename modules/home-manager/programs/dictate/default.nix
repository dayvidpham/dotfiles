{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.programs.dictate;

  # Everything the scripts shell out to, so they do not depend on the session
  # PATH of whoever installs this.
  runtimePath = lib.makeBinPath [
    pkgs.pipewire # pw-record, pw-play
    pkgs.curl
    pkgs.wl-clipboard # wl-copy
    pkgs.coreutils # mkfifo, rm, mkdir, cat, readlink
  ];

  dictate = pkgs.stdenvNoCC.mkDerivation {
    pname = "dictate";
    version = "0.3.0";
    src = ./.;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share/dictate
      install -m755 dictate.sh $out/bin/dictate
      install -m755 dictate-status.sh $out/bin/dictate-status
      install -m644 sounds/*.wav $out/share/dictate/
      runHook postInstall
    '';
    postFixup = ''
      for program in dictate dictate-status; do
        wrapProgram $out/bin/$program --prefix PATH : ${runtimePath}
      done
    '';
  };
in
{
  options.CUSTOM.programs.dictate = {
    enable = lib.mkEnableOption "the dictate client and its waybar indicator";
  };

  config = lib.mkIf cfg.enable {
    # `dictate` records through a FIFO into the dictated service and copies the
    # transcript; `dictate-status` feeds the waybar indicator.
    home.packages = [ dictate ];
  };
}
