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
    # libva1 (legacy libva.so.1 ABI shim, pinned to 1.8.3) removed for 26.05:
    # its 2017-era va_nvctrl.c fails to compile under GCC's now-default
    # -Werror=incompatible-pointer-types. Modern VAAPI / nvidia-vaapi-driver
    # link libva.so.2 (kept via `libva` above); only ancient prebuilt binaries
    # hardcoded against libva.so.1 would need this back.
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
