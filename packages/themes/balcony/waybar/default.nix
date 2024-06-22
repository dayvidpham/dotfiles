{ stdenv
, lib
, makeWrapper
, waybar
, rofi
, rofi-bluetooth
  #, rofi-network-manager
, networkmanager
, playerctl
, python3
, ...
}@inputs:
let
  waybar-mediaPlayer = (waybar.override { withMediaPlayer = true; });
  python3-deps = (python3.withPackages (pyPkgs: with pyPkgs; [
    requests
  ]));
  pkg = stdenv.mkDerivation (finalAttrs: {
    pname = "waybar-balcony";
    version = "0.0.1";
    src = ./.;

    nativeBuildInputs = [
      makeWrapper
    ];

    buildInputs = [
      rofi
      rofi-bluetooth
      #rofi-network-manager
      networkmanager
      waybar-mediaPlayer
      playerctl
      python3-deps
    ];

    # NOTE: The dest dir is needed in cp, else will copy as <store-path>-scripts
    # CORRECT:    cp -r ${./scripts} $out/share/scripts
    # INCORRECT:  cp -r ${./scripts} $out/share
    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -r ${waybar-mediaPlayer}/bin $out/bin

      mkdir -p $out/share/waybar
      cp -r ./scripts $out/share/waybar/scripts
      chmod +x $out/share/waybar/scripts/spotify.sh
      chmod +x $out/share/waybar/scripts/hello.sh
      chmod +x $out/share/waybar/scripts/weather.py

      mkdir -p $out/config/waybar
      cp ./config $out/config/waybar/config
      cp ./config.nix $out/config/waybar/config.nix
      cp ./style.css $out/config/waybar/style.css

      runHook postInstall
    '';

    preFixup = ''
      wrapProgram $out/share/waybar/scripts/spotify.sh \
        --suffix PATH "${lib.makeBinPath [ playerctl ]}"

      wrapProgram $out/share/waybar/scripts/weather.py \
        --set PYTHONPATH "${python3-deps}/${python3-deps.sitePackages}"
    '';
    #--prefix PYTHONPATH : "$out/${python3-deps.sitePackages}"


    passthru =
      let
        outPath = finalAttrs.finalPackage.outPath;
        inherit (lib) fileContents;
      in
      {
        finalAttrs = finalAttrs;
        original = pkg;

        config = (import (outPath + "/config/waybar/config.nix") {
          scriptsDir = finalAttrs.finalPackage.passthru.scripts;
        });
        style = fileContents (outPath + "/config/waybar/style.css");
        scripts = outPath + "/share/waybar/scripts";
      };
  });
in
pkg
