{ stdenv
, lib
, waybar
, rofi
, rofi-bluetooth
  #, rofi-network-manager
, networkmanager
, playerctl
, python3
  #, pkgs
  #, lib ? pkgs.lib
  #, rofi ? pkgs.rofi-wayland-unwrapped
, ...
}@inputs:
let
  waybar-mediaPlayer = (waybar.override { withMediaPlayer = true; });
in
waybar-mediaPlayer.overrideAttrs (finalAttrs: prevAttrs: {
  pname = "waybar-balcony";

  #buildInputs = prevAttrs.buildInputs ++ [
  #  python3
  #];

  propagatedBuildInputs = prevAttrs.propagatedBuildInputs ++ [
    rofi
    rofi-bluetooth
    #rofi-network-manager
    networkmanager
    python3
    python3.pkgs.requests
  ];

  postInstall =
    let
      # NOTE: The dest dir is needed in cp, else will copy as <store-path>-scripts
      # CORRECT:    cp -r ${./scripts} $out/share/scripts
      # INCORRECT:  cp -r ${./scripts} $out/share
      stub = ''
        mkdir -p $out/share

        cp -r ${./scripts} $out/share/scripts
        cp ${./config} $out/share/config
        cp ${./style.css} $out/share/style.css

        chmod +x $out/share/scripts/spotify.sh
        chmod +x $out/share/scripts/weather.py
      '';

      postInstall' =
        if (prevAttrs ? postInstall)
        then prevAttrs.postInstall
        else "";
    in
    postInstall' + stub;

  preFixup =
    let
      preFixup' =
        if (prevAttrs ? preFixup)
        then prevAttrs.preFixup
        else "";
    in
    preFixup' + ''
      wrapProgram $out/share/scripts/spotify.sh \
        --suffix PATH : "${lib.makeBinPath [ playerctl ]}"

      wrapProgram $out/share/scripts/weather.py \
        --suffix PYTHONPATH : "$out/${python3.sitePackages}"
    '';
})
