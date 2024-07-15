{ stdenv
, symlinkJoin
, lib
, makeWrapper
, waybar
, rofi
, rofi-bluetooth
  #, rofi-network-manager
, networkmanager
, playerctl
, python3
, pavucontrol
, hyprlock
}@inputs:
let
  inherit (builtins)
    replaceStrings
    ;

  inherit (lib)
    fileContents
    getExe
    ;

  waybar-mediaPlayer = (waybar.override { withMediaPlayer = true; });
  python3-deps = (python3.withPackages (pyPkgs: with pyPkgs; [
    requests
  ]));

  derivationArgs = (finalAttrs: {
    pname = "waybar-balcony-config";
    version = "0.0.3";
    src = ./.;
    allowSubstitutes = false; # custom package will never be found in online cache

    nativeBuildInputs = [
      makeWrapper
    ];

    buildInputs = [
      python3-deps
      rofi
      #rofi-bluetooth
      #rofi-network-manager
      #networkmanager
      #waybar-mediaPlayer
      #playerctl
    ];

    # WARN: The dest dir is needed in cp, else will copy as <store-path>-scripts
    # CORRECT:    cp -r ${./scripts} $out/share/scripts
    # INCORRECT:  cp -r ${./scripts} $out/share

    buildPhase = ''
      runHook preBuild
      
      mkdir -p $src

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      cp -r ./share $out/share
      chmod +x $out/share/waybar/scripts/spotify.sh
      chmod +x $out/share/waybar/scripts/hello.sh
      chmod +x $out/share/waybar/scripts/weather.py
      chmod +x $out/share/waybar/scripts/power-menu/powermenu.sh

      cp -r ./config $out/config

      runHook postInstall
    '';

    preFixup = ''
      wrapProgram $out/share/waybar/scripts/spotify.sh \
        --suffix PATH : "${lib.makeBinPath [ playerctl ]}"

      wrapProgram $out/share/waybar/scripts/weather.py \
        --set PYTHONPATH "${python3-deps}/${python3-deps.sitePackages}"

      wrapProgram $out/share/waybar/scripts/power-menu/powermenu.sh \
        --prefix PATH : "${lib.makeBinPath [ rofi ]}"
    '';

    passthru =
      let
        outPath = finalAttrs.finalPackage.outPath;
        scripts = outPath + "/share/waybar/scripts";
        style = fileContents (outPath + "/config/waybar/style.css");
      in
      {
        inherit
          finalAttrs
          scripts
          style
          ;
        original = waybar-balcony;

        settings = (import ./config/waybar/config.nix {
          inherit
            rofi
            playerctl
            pavucontrol
            hyprlock
            getExe
            waybar-mediaPlayer
            ;

          scriptsDir = scripts;
        });
      };
  });

  waybar-balcony-config = stdenv.mkDerivation derivationArgs;

  waybar-balcony = symlinkJoin ({
    inherit (waybar-balcony-config) passthru;
    name = replaceStrings
      [ "waybar-balcony-config" ] [ "waybar-balcony" ]
      waybar-balcony-config.name;
    paths = [ waybar-mediaPlayer waybar-balcony-config ];
  });
in
waybar-balcony
