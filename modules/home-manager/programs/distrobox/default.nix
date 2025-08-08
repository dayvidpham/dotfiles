{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.distrobox;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.programs.distrobox = {
    enable = mkEnableOption "distrobox config";
  };

  config = mkIf cfg.enable {
    programs.distrobox.enable = true;
    programs.distrobox.containers = {
      debian-common = {
        image = "debian:13";
        entry = true;
        additional_packages = "git";
        init_hooks = [
          "ln -sf /usr/bin/distrobox-host-exec /usr/local/bin/docker"
          "ln -sf /usr/bin/distrobox-host-exec /usr/local/bin/docker-compose"
        ];
      };

      sfurs = {
        clone = "debian-common";
        additional_packages = "
        git
        build-essential
        cmake
        ninja-build
        pkg-config
        qt6-base-dev
        qt6-declarative-dev
        qt6-remoteobjects-dev
        libqt6remoteobjects6
        libqt6remoteobjects6-bin
        qml6-module-qtquick
        qml6-module-qtquick-window
        qml6-module-qtquick-controls
        qml6-module-qtquick-templates
        qml6-module-qtquick-layouts
        qml6-module-qtqml-workerscript
        qml6-module-qtremoteobjects
        libqt5opengl5-dev
        libgl1-mesa-dev
        libglu1-mesa-dev
        libprotobuf-dev
        protobuf-compiler
        libode-dev
        libboost-dev
        mesa-common-dev
        libxcb1
        libxcb-icccm4
        libxcb-image0
        libxcb-keysyms1
        libxcb-randr0
        libxcb-render-util0
        libxcb-shape0
        libxcb-xinerama0
        libxcb-xkb1
        libxkbcommon-x11-0
        python3
        python3-pip
        python3-pybind11
        python3-dev
      ";
        entry = false;
        nvidia = true;
      };
    };
  };
}
