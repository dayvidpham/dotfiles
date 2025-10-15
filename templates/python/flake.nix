{
  description = "Provides a reproducible python3 env to run the simulations";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-python.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    inputs@{ self
    , nixpkgs-stable
    , nixpkgs-unstable
    , nixpkgs-python
    , flake-utils
    , ...
    }:
    let
      mkEnvFromChannel = (nixpkgs-channel: nixpkgs-channel-python:
        flake-utils.lib.eachDefaultSystem (system:
          let
            pkgs = import nixpkgs-channel {
              inherit system;
              config.allowUnfree = true;
              config.cudaSupport = true;
              config.cudaVersion = "12";
            };
            pkgs-python = import nixpkgs-channel-python {
              inherit system;
              config.allowUnfree = true;
              config.cudaSupport = true;
              config.cudaVersion = "12";
            };

            #########################################
            # Defines python dependencies

            python3-pkgName = "python313";

            f-python3-prodPkgs = (python-pkgs: (with python-pkgs; [
              pip
              virtualenv
              gymnasium
              matplotlib
              mujoco
              numpy
              torch
            ]) ++ [
            ]);

            python3-pkg = pkgs-python."${python3-pkgName}";
            python3-deps = pkgs-python."${python3-pkgName}Packages";

            python3-with-pkgs =
              let
                python3Pkg = pkgs-python."${python3-pkgName}";
                python3Packages = pkgs-python."${python3-pkgName}Packages";
              in
              python3Pkg.buildEnv.override {
                extraLibs = [ ]
                  ++ (f-python3-prodPkgs python3Packages)
                ;
                ignoreCollisions = true;
              };


            f-python3-buildInputs = (pkgs_: with pkgs_; [
              zlib
              glibc
              stdenv.cc.cc.lib
              gcc
              tk
              tcl
            ]);


            nvidiaPackage = pkgs.linuxPackages.nvidiaPackages.stable;
            f-nvidia-buildInputs = (pkgs_: with pkgs_; [
              ffmpeg
              fmt.dev
              cudaPackages.cuda_cudart
              cudatoolkit
              nvidiaPackage
              cudaPackages.cudnn
              libGLU
              libGL
              xorg.libXi
              xorg.libXmu
              freeglut
              xorg.libXext
              xorg.libX11
              xorg.libXv
              xorg.libXrandr
              zlib
              ncurses
              stdenv.cc
              binutils
              uv
              wayland
            ]);

            f-nvidia-shellHook = (pkgs_: with pkgs_; ''
              export LD_LIBRARY_PATH="${nvidiaPackage}/lib:${pkgs_.wayland}/lib:$LD_LIBRARY_PATH"
              export CUDA_PATH=${pkgs_.cudatoolkit}
              export EXTRA_LDFLAGS="-L/lib -L${nvidiaPackage}/lib"
              export EXTRA_CCFLAGS="-I/usr/include"
              export CMAKE_PREFIX_PATH="${pkgs_.fmt.dev}:$CMAKE_PREFIX_PATH"
              export PKG_CONFIG_PATH="${pkgs_.fmt.dev}/lib/pkgconfig:$PKG_CONFIG_PATH"
              export MUJOCO_GL="egl"
            '');


            #########################################
            # Will be used to define
            # outputs.devShells

            devShell = pkgs.mkShell {
              name = "sw-rl-agent";

              buildInputs = (with pkgs-python; [

              ]
              ++ f-python3-buildInputs pkgs-python
              ++ f-nvidia-buildInputs pkgs-python
              );

              inputsFrom = ([

              ]
              ++ f-python3-prodPkgs pkgs-python."${python3-pkgName}Packages"
              );

              packages = [
                #pkgs-python.micromamba
                pkgs-python.uv
                python3-pkg
              ];

              shellHook =
                let
                  tk = pkgs.tk;
                  tcl = pkgs.tcl;
                in
                ''
                  export LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH"
                  export TK_LIBRARY="${tk}/lib/${tk.libPrefix}"
                  export TCL_LIBRARY="${tcl}/lib/${tcl.libPrefix}"

                  ${f-nvidia-shellHook pkgs}
                '';

              allowSubstitutes = false;
            };

            fhsEnv = (pkgs.buildFHSEnv
              {
                name = "sw-rl-agent-fhsEnv";
                targetPkgs = (fhs-pkgs:
                  [
                    fhs-pkgs.uv
                    fhs-pkgs.git
                  ]
                  ++ (f-python3-buildInputs fhs-pkgs)
                  ++ (f-nvidia-buildInputs fhs-pkgs)
                );

                multiPkgs = fhs-pkgs: with fhs-pkgs; [ zlib ];

                runScript = "zsh";

                profile = ''
                  ${f-nvidia-shellHook pkgs}
                '';

                allowSubstitutes = false;
              }).env;
          in
          {
            devShells.default = devShell;
            devShells.build = fhsEnv;
          }
        ));
    in
    mkEnvFromChannel
      nixpkgs-unstable
      nixpkgs-unstable;
}
