{ stdenv
, lib
, waybar-wayland-unwrapped
, wrapProgram
, rofi
, rofi-bluetooth
, rofi-network-manager
, networkmanager
, playerctl
, python3
  #, pkgs
  #, lib ? pkgs.lib
  #, rofi ? pkgs.rofi-wayland-unwrapped
}:
let
  waybar-balcony = (waybar-wayland-unwrapped.overrideAttrs (finalAttrs: prevAttrs: {
    pname = "waybar-wayland-balcony";

    nativeBuildInputs = prevAttrs.nativeBuildInputs ++ [
      wrapProgram
    ];

    #buildInputs = prevAttrs.buildInputs ++ [
    #  python3
    #];

    propagatedBuildInputs = prevAttrs.propagatedBuildInputs ++ [
      rofi
      rofi-bluetooth
      rofi-network-manager
      networkmanager
      python3
      python3.pkgs.requests
    ];

    preFixup = prevAttrs + ''
      mkdir -p $out/share
      cp -r ${./scripts} $out/share
      cp ${./config} $out/share
      cp ${./style.css} $out/share
    '';

    #wrapProgram $out/share/scripts/mediaplayer.py \
    #  --suffix PATH ${lib.makeBinPath [
    #    rofi
    #    playerctl
    #  ]}
    #  --suffix PYTHONPATH ${lib.makeBinPath [
    #    python3.pkgs.requests
    #  ]}
    postFixup = prevAttrs + ''
      wrapProgram $out/share/scripts/spotify.sh \
        --suffix PATH ${lib.makeBinPath [
          playerctl
        ]}

      wrapProgram $out/share/scripts/weather.py \
        --suffix PYTHONPATH ${lib.makeBinPath [
          python3.pkgs.requests
        ]}
    '';
  }));
in
{ }

