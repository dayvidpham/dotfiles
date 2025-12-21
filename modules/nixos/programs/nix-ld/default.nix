# NOTE: Referenced from:
# https://github.com/Mic92/dotfiles/blob/a1b8a16b393d4396a0f41144d3cf308453d66048/nixos/modules/nix-ld.nix
{ config, pkgs, lib, ... }: {
  programs.nix-ld.enable = true;
  programs.nix-ld.package = pkgs.nix-ld;
  programs.nix-ld.libraries = with pkgs; [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    binutils
    cairo
    cups
    curl
    dbus
    expat
    fontconfig
    freetype
    freeglut
    fuse3
    gdk-pixbuf
    glib
    gtk3
    icu
    libGL
    libappindicator-gtk3
    libdrm
    libglvnd
    libnotify
    libpulseaudio
    libunwind
    libusb1
    libuuid
    libxkbcommon
    libxml2
    libva
    libva1
    nvidia-vaapi-driver
    mesa
    libgbm
    nspr
    nss
    openssl
    pango
    pipewire
    stdenv.cc.cc
    systemd
    vulkan-loader
    xorg.libX11
    xorg.libXScrnSaver
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXinerama
    xorg.libXmu
    xorg.libXrandr
    xorg.libXrender
    xorg.libXtst
    xorg.libXv
    xorg.libxcb
    xorg.libxkbfile
    xorg.libxshmfence
    zlib
    wayland
  ]
  ++ lib.optionals (config.CUSTOM.hardware.nvidia.enable) [
    pkgs.cudaPackages.cuda_cudart
    pkgs.cudatoolkit
    config.CUSTOM.hardware.nvidia.proprietaryDrivers.package
    pkgs.cudaPackages.cudnn
  ];
}
