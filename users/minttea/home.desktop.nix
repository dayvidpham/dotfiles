{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
let
  extra-path = with pkgs; [
    dotnet-sdk_8
    mono
    msbuild
    nuget
    # Add any extra binaries you want accessible to Rider here
  ];


  extra-lib = with pkgs;[
    # Add any extra libraries you want accessible to Rider here
  ];


  rider = pkgs.jetbrains.rider.overrideAttrs (attrs: {
    postInstall = ''
      # Wrap rider with extra tools and libraries

      mv $out/bin/rider $out/bin/.rider-toolless
      makeWrapper $out/bin/.rider-toolless $out/bin/rider \
        --argv0 rider \
        --prefix PATH : "${lib.makeBinPath extra-path}" \
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath extra-lib}"

      # Making Unity Rider plugin work!
      # The plugin expects the binary to be at /rider/bin/rider,
      # with bundled files at /rider/
      # It does this by going up two directories from the binary path
      # Our rider binary is at $out/bin/rider, so we need to link $out/rider/ to $out/

      shopt -s extglob
      ln -s $out/rider/!(bin) $out/
      shopt -u extglob
    '' + attrs.postInstall or "";
  });

in
{
  ########################
  # Wayland Desktop Envs

  CUSTOM.wayland.windowManager.hyprland = {
    enable = true;
  };

  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = true;
  };


  home.packages = (with pkgs; [
    # Gaming
    protonup-ng

    # Game Dev
    #godot
  ])
  ++ (with pkgs-unstable; [
    # CAD viewer
    #blender
  ])
  ++ [
    rider
  ]
  ;

  CUSTOM.programs.vscode.enable = true;
  CUSTOM.programs.unity.enable = true;
  CUSTOM.games.minecraft.enable = false;
  programs.lutris.enable = true;

  CUSTOM.services.syncthing.enable = true;

  ##################
  # Virtualisation

  CUSTOM.services.podman.enable = true;
  CUSTOM.programs.distrobox.enable = true;
  CUSTOM.virtualisation.libvirtd.enable = true;
}
