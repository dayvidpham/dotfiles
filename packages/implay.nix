{ stdenv
, cmake
, pkg-config
, glfw
, mpv-unwrapped
, freetype
, gtk3
, wayland
, cudatoolkit
}:
stdenv.mkDerivation {
  name = "ImPlay";

  src = builtins.fetchGit {
    url = "git@github.com:tsl0922/ImPlay.git";
    shallow = true;
    rev = "d3f85011b6a89cf85a8ba310e56f51bbaf62208d";
  };

  buildInputs = [
    glfw
    mpv-unwrapped
    freetype
    gtk3
    wayland
    cudatoolkit
  ];

  nativeBuildInputs = [
    cmake
    stdenv.cc
    pkg-config
  ];

  allowSubstitutes = false;
}
