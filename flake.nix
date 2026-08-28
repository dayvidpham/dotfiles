{
  description = "Base configuration using flake to manage NixOS";

  # Inputs
  # https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    #############################
    # NixOS-related inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-wsl.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    #############################
    # Nix package management
    determinate-nix.url = "https://flakehub.com/f/DeterminateSystems/nix-src/*";
    determinate-nixd.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    home-manager-wsl = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs-wsl";
    };

    #############################
    # Other software
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-stable";
      inputs.nixpkgs-stable.follows = "nixpkgs-stable";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    tuicr = {
      url = "github:agavra/tuicr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #----------------------------------------
    # My stuff

    pasture = {
      url = "github:dayvidpham/pasture";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    aura-plugins = {
      url = "github:dayvidpham/aura-plugins";
      inputs.nixpkgs.follows = "nixpkgs-stable";
      inputs.nixpkgs-stable.follows = "nixpkgs-stable";
      inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
    };

    openclaw-modules = {
      url = "github:dayvidpham/nix-openclaw-vm/develop";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    beads = {
      url = "github:dayvidpham/beads/main-fork";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    strike = {
      url = "github:jonathanung/strike";
      inputs.nixpkgs.follows = "nixpkgs";
    };


    #----------------------------------------
    # Zig
    zig-flake = {
      url = "github:silversquirl/zig-flake/compat";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zls = {
      url = "github:zigtools/zls";
      inputs.zig-flake.follows = "zig-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #----------------------------------------
    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self
      # NixOS-related
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-stable
    , nixos-hardware
    , nixpkgs-wsl
    , nixos-wsl
    , flake-registry
      # Package management
    , determinate-nix
    , determinate-nixd
    , home-manager
    , home-manager-wsl
      # Community tools
    , niri
    , llm-agents
    , microvm
    , nix-openclaw
    , sops-nix
    , zig-flake
    , zls
    , tuicr
      # My stuff
    , openclaw-modules
    , aura-plugins
    , beads
    , pasture
    , strike
    , ...
    }:
    let
      system = "x86_64-linux";
      nixpkgs-options = {
        inherit system;

        config = {
          allowUnfree = true;
          cudaSupport = true;
        };

        overlays = [
          # tuicr
          (final: prev: {
            tuicr = tuicr.packages.${system}.default;
          })

          # zig tools
          (final: prev: {
            zig_nightly = zig-flake.packages.${system}.nightly;
            zls_nightly = zls.packages.${system}.zls;
          })


          # NOTE: determinate-nix.overlays.default removed — wasmtime.nix requires
          # rust_1_89 which was dropped from nixpkgs 25.11 (only rust_1_91 remains).
          # Re-enable when DeterminateSystems ships a compatible release.
          #determinate-nix.overlays.default
          (prev: final: {
            llm-agents = llm-agents.packages.${system};
          })

          nix-openclaw.overlays.default

          # Override openclaw to disable extended tools (whisper/torch/triton)
          # Note: nodejs/pnpm excluded to avoid collision with system packages
          (final: prev: {
            openclaw = prev.openclaw.override {
              extendedTools = with final; [
                git
                curl
                jq
                python3
                ffmpeg
                ripgrep
                go
                uv
              ];
            };
          })

          # Beads issue tracker — wrap with dolt runtime dependency
          (final: prev: {
            beads =
              let
                base = beads.packages.${final.stdenv.hostPlatform.system}.default;
              in
              final.runCommand "beads-wrapped"
                {
                  nativeBuildInputs = [ final.makeWrapper ];
                } ''
                mkdir -p $out/bin
                cp -r ${base}/* $out/
                wrapProgram $out/bin/bd --prefix PATH : ${final.lib.makeBinPath [ final.dolt ]}
                ln -sf bd $out/bin/beads
              '';
          })

          # NOTE: My own packages and programs
          (final: prev: {
            run-cwd = with prev; callPackage ./packages/run-cwd.nix { };
            scythe = with prev; callPackage ./packages/scythe.nix {
              wl-clipboard = wl-clipboard-rs;
              output-dir = "$HOME/Pictures/scythe";
            };
            waybar-balcony = with prev; callPackage ./packages/themes/balcony/waybar {
              rofi = rofi-unwrapped;
            };
            ImPlay = with prev; callPackage ./packages/implay.nix { };
          })
        ];
      };

      pkgs = import nixpkgs nixpkgs-options;
      pkgs-unstable = import nixpkgs-unstable nixpkgs-options;
      pkgs-stable = import nixpkgs-stable nixpkgs-options;
      pkgs-wsl = import nixpkgs-wsl nixpkgs-options;

      lib = pkgs.lib;

      #############################
      # Feature Module Registry
      # Maps feature names to their corresponding NixOS modules
      # These are OPTIONAL features that hosts can enable
      featureModules = {
        # WSL support (only needed for WSL hosts)
        wsl = nixos-wsl.nixosModules.default // {
          system.build.installBootLoader = lib.mkForce "${pkgs.coreutils}/bin/true";
        };
      };

      #############################
      # Base modules included in ALL standard hosts
      # This ensures consistent module availability - features are controlled via enable options
      baseModules = [
        # Core infrastructure
        determinate-nixd.nixosModules.default
        niri.nixosModules.niri
        microvm.nixosModules.host
        sops-nix.nixosModules.sops
        openclaw-modules.nixosModules.default

        # Custom modules
        ./modules/nixos
        noChannelModule
      ];

      # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
      noChannelModule = {
        nix.settings.experimental-features = [ "nix-command" "flakes" "fetch-closure" ];
        nix.channel.enable = false;

        nix.registry.nixpkgs.flake = nixpkgs;
        nix.registry.home-manager.flake = home-manager;
        nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;
        nix.registry.nixpkgs-stable.flake = nixpkgs-stable;
        environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
        environment.etc."nix/inputs/nixpkgs-unstable".source = "${nixpkgs-unstable}";
        environment.etc."nix/inputs/nixpkgs-stable".source = "${nixpkgs-stable}";
        environment.etc."nix/inputs/home-manager".source = "${home-manager}";
        environment.etc."nixos/flake.nix".source = "/home/minttea/dotfiles/flake.nix";

        nix.nixPath = [
          "nixos-config=/etc/nixos/flake.nix"
          "nixpkgs=/etc/nix/inputs/nixpkgs"
          "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
          "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
          "home-manager=/etc/nix/inputs/home-manager"
        ];
        nix.settings.nix-path = [
          "nixos-config=/etc/nixos/flake.nix"
          "nixpkgs=/etc/nix/inputs/nixpkgs"
          "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
          "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
          "home-manager=/etc/nix/inputs/home-manager"
        ];

        nix.settings.flake-registry = "${flake-registry}/flake-registry.json";
      };

      # NOTE: Utils and enum types
      libmint =
        import ./modules/nixos/libmint.nix {
          inherit lib;
          lib-hm = home-manager.outputs.lib.hm;
          inherit (pkgs) runCommandLocal;
        };

      # NOTE: Common args to be passed to nixosConfigs and homeConfigurations
      specialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          libmint
          niri
          microvm
          nix-openclaw
          beads
          sops-nix
          ;
        # Shim: openclaw-vm module expects opencode flake output shape
        # but we consume opencode from llm-agents overlay instead
        opencode = { packages.${system}.opencode = pkgs-unstable.llm-agents.opencode; };
      };

      extraSpecialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          niri
          nix-openclaw
          beads
          strike
          pasture
          sops-nix
          ;
      };

      #############################
      # Host Builder
      # Creates a NixOS configuration with base modules + optional features
      #
      # All hosts get the same base modules (sops, niri, microvm, etc.)
      # Features are controlled via enable options in host configuration
      # Only truly host-specific modules (like WSL) are passed as features
      #
      # Arguments:
      #   name: Host name (used to find ./hosts/${name}/configuration.nix)
      #   features: List of optional feature names (e.g., ["wsl"])
      #   extraModules: Additional modules to include (optional)
      #   hostSpecialArgs: Additional specialArgs to merge (optional)
      mkHost =
        { name
        , features ? [ ]
        , extraModules ? [ ]
        , hostSpecialArgs ? { }
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = specialArgs // hostSpecialArgs;
          modules =
            # Base modules (always included)
            baseModules
            # Optional feature modules (from registry)
            ++ (builtins.map (f: featureModules.${f}) features)
            # Host-specific configuration
            ++ [ ./hosts/${name}/configuration.nix ]
            # Any additional modules
            ++ extraModules;
        };

      # Minimal host builder for special cases (e.g., microVMs)
      mkMinimalHost =
        { name
        , modules
        , hostSpecialArgs ? { }
        }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = hostSpecialArgs;
          modules = modules;
        };

    in
    {
      # Used with `nixos-rebuild --flake .#<hostname>`
      # nixosConfigurations."<hostname>".config.system.build.toplevel must be a derivation
      nixosConfigurations = {
        # Standard workstation hosts - all base modules included automatically
        flowX13 = mkHost {
          name = "flowX13";
          extraModules = [
            ({ config, lib, ... }@args:
              lib.mkIf (!config.isSpecialisation)
                (import nixos-hardware.nixosModules.common-gpu-nvidia-disable args))
          ];
        };
        desktop = mkHost { name = "desktop"; };

        # WSL hosts - need the wsl feature module
        wsl = mkHost {
          name = "wsl";
          features = [ "wsl" ];
        };

        flowX13-wsl = mkHost {
          name = "flowX13-wsl";
          features = [ "wsl" ];
        };

        # LLM Sandbox microVM - minimal standalone configuration
        # Note: specialArgs.pkgs warning is expected - microvm module design
        llm-sandbox = mkMinimalHost {
          name = "llm-sandbox";
          hostSpecialArgs = { inherit pkgs pkgs-unstable; };
          modules = [
            microvm.nixosModules.microvm
            ./modules/nixos/virtualisation/llm-sandbox/guest.nix
          ];
        };

        # OpenClaw microVM - runs openclaw gateway with network access to safemolt
        openclaw-vm = mkMinimalHost {
          name = "openclaw-vm";
          hostSpecialArgs = {
            inherit pkgs pkgs-unstable nix-openclaw;
            # Shim: openclaw-vm module expects opencode flake output shape
            # but we consume opencode from llm-agents overlay instead
            opencode = { packages.${system}.opencode = pkgs-unstable.llm-agents.opencode; };
          };
          modules = [
            microvm.nixosModules.microvm
            openclaw-modules.nixosModules.openclaw-vm-guest
          ];
        };
      };

      checks.${system}.flowX13-gpu-profiles =
        let
          base = self.nixosConfigurations.flowX13.config;
          enabled = base.specialisation.nvidia-enabled.configuration;
          baseToplevel = base.system.build.toplevel;
          enabledToplevel = enabled.system.build.toplevel;
          baseUdev = base.services.udev.extraRules;
          enabledUdev = enabled.services.udev.extraRules;
          baseModprobe = base.boot.extraModprobeConfig;
          enabledModprobe = enabled.boot.extraModprobeConfig;
          upstreamClasses = [ "0x0c0330" "0x0c8000" "0x040300" "0x03[0-9]*" ];
          upstreamModules = [ "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" ];
          disabledOnlyModules = [ "nvidia" "nvidia_drm" "nvidia_modeset" ];
          enabledVideoDrivers = [ "nvidia" "amdgpu" "modesetting" ];
          hasAll = values: collection: builtins.all (value: builtins.elem value collection) values;
          hasNo = values: collection: builtins.all (value: !(builtins.elem value collection)) values;
          containsAll = values: text: builtins.all (value: lib.hasInfix value text) values;
          containsNo = values: text: builtins.all (value: !(lib.hasInfix value text)) values;
          cudaPackages = [ pkgs.cudatoolkit pkgs.cudaPackages.cudnn pkgs.cudaPackages.cuda_cudart ];
          drmLinks = {
            card-igpu = "/dev/dri/by-path/pci-0000:08:00.0-card";
            card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
            render-igpu = "/dev/dri/by-path/pci-0000:08:00.0-render";
            render-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-render";
          };
          enabledNiriConfig = enabled.environment.sessionVariables.NIRI_CONFIG;
          loaderConfig = base.boot.loader.systemd-boot.extraFiles."loader/loader.conf";
        in
        assert lib.assertMsg (!base.isSpecialisation) "Flow X13 base must not evaluate as a specialization";
        assert lib.assertMsg (!base.CUSTOM.hardware.nvidia.enable) "Flow X13 base must keep custom NVIDIA policy disabled";
        assert lib.assertMsg (!base.CUSTOM.hardware.nvidia.proprietaryDrivers.enable) "Flow X13 base must keep proprietary NVIDIA policy disabled";
        assert lib.assertMsg (base.services.xserver.videoDrivers == [ "modesetting" ]) "Flow X13 base must select only the modesetting X server driver";
        assert lib.assertMsg (!base.services.supergfxd.enable) "Flow X13 base must keep supergfxd disabled";
        assert lib.assertMsg (!base.hardware.nvidia.prime.sync.enable) "Flow X13 base must not enable PRIME sync";
        assert lib.assertMsg (!base.hardware.nvidia.prime.reverseSync.enable) "Flow X13 base must not enable reverse PRIME sync";
        assert lib.assertMsg (!base.hardware.nvidia.prime.offload.enable) "Flow X13 base must not enable PRIME offload";
        assert lib.assertMsg (hasNo cudaPackages base.environment.systemPackages) "Flow X13 base must not include enabled-only CUDA packages";
        assert lib.assertMsg (!(base.environment.variables ? WLR_DRM_DEVICES)) "Flow X13 base must not set WLR_DRM_DEVICES";
        assert lib.assertMsg (containsAll upstreamClasses baseUdev) "Flow X13 base is missing an upstream NVIDIA PCI removal rule";
        assert lib.assertMsg (hasAll upstreamModules base.boot.blacklistedKernelModules) "Flow X13 base is missing an upstream NVIDIA kernel-module blacklist entry";
        assert lib.assertMsg (containsAll [ "blacklist nouveau" "options nouveau modeset=0" ] baseModprobe) "Flow X13 base is missing the upstream nouveau modprobe policy";
        assert lib.assertMsg enabled.isSpecialisation "Flow X13 nvidia-enabled must evaluate as a specialization";
        assert lib.assertMsg enabled.CUSTOM.hardware.nvidia.enable "Flow X13 nvidia-enabled must enable custom NVIDIA policy";
        assert lib.assertMsg enabled.CUSTOM.hardware.nvidia.proprietaryDrivers.enable "Flow X13 nvidia-enabled must select proprietary NVIDIA policy";
        assert lib.assertMsg (enabled.services.xserver.videoDrivers == enabledVideoDrivers) "Flow X13 nvidia-enabled must select the exact NVIDIA, AMDGPU, and modesetting driver list";
        assert lib.assertMsg enabled.hardware.nvidia.modesetting.enable "Flow X13 nvidia-enabled must enable NVIDIA DRM modesetting";
        assert lib.assertMsg enabled.hardware.nvidia.prime.sync.enable "Flow X13 nvidia-enabled must use PRIME sync";
        assert lib.assertMsg (!enabled.hardware.nvidia.prime.reverseSync.enable) "Flow X13 nvidia-enabled must not use reverse PRIME sync";
        assert lib.assertMsg (!enabled.hardware.nvidia.prime.offload.enable) "Flow X13 nvidia-enabled must not use PRIME offload";
        assert lib.assertMsg (!enabled.hardware.nvidia.prime.offload.enableOffloadCmd) "Flow X13 nvidia-enabled must not install the PRIME offload command";
        assert lib.assertMsg (!enabled.hardware.nvidia.powerManagement.finegrained) "Flow X13 nvidia-enabled must not use fine-grained offload power management";
        assert lib.assertMsg (enabled.hardware.nvidia.prime.nvidiaBusId == "PCI:1:0:0") "Flow X13 nvidia-enabled has the wrong NVIDIA PRIME bus ID";
        assert lib.assertMsg (enabled.hardware.nvidia.prime.amdgpuBusId == "PCI:8:0:0") "Flow X13 nvidia-enabled has the wrong AMD PRIME bus ID";
        assert lib.assertMsg (!enabled.services.supergfxd.enable) "Flow X13 nvidia-enabled must keep supergfxd disabled";
        assert lib.assertMsg (hasAll cudaPackages enabled.environment.systemPackages) "Flow X13 nvidia-enabled must include the CUDA runtime closure";
        assert lib.assertMsg (hasAll (builtins.attrNames drmLinks) (builtins.attrNames enabled.environment.etc)) "Flow X13 nvidia-enabled must expose all card and render device links";
        assert lib.assertMsg (!(enabled.environment.variables ? WLR_DRM_DEVICES)) "Flow X13 nvidia-enabled must not set WLR_DRM_DEVICES";
        assert lib.assertMsg (enabledNiriConfig != null) "Flow X13 nvidia-enabled must select its generated Niri config";
        assert lib.assertMsg (containsNo upstreamClasses enabledUdev) "Flow X13 nvidia-enabled inherited an upstream NVIDIA PCI removal rule";
        assert lib.assertMsg (hasNo disabledOnlyModules enabled.boot.blacklistedKernelModules) "Flow X13 nvidia-enabled inherited a disable-only NVIDIA kernel-module blacklist entry";
        assert lib.assertMsg (containsNo [ "blacklist nouveau" "options nouveau modeset=0" ] enabledModprobe) "Flow X13 nvidia-enabled inherited the upstream nouveau modprobe policy";
        assert lib.assertMsg (builtins.attrNames base.specialisation == [ "nvidia-enabled" ]) "Flow X13 must expose only the nvidia-enabled specialization";
        pkgs.runCommand "flowX13-gpu-profiles"
          {
            nativeBuildInputs = [ niri.packages.${system}.niri-stable ];
          }
          ''
            grep -F 'render-drm-device "/dev/dri/by-path/pci-0000:01:00.0-render"' ${enabledNiriConfig}
            niri validate --config ${enabledNiriConfig}
            grep -F 'default @saved' ${loaderConfig}
            test "$(readlink ${enabled.environment.etc.card-igpu.source})" = ${lib.escapeShellArg drmLinks.card-igpu}
            test "$(readlink ${enabled.environment.etc.card-dgpu.source})" = ${lib.escapeShellArg drmLinks.card-dgpu}
            test "$(readlink ${enabled.environment.etc.render-igpu.source})" = ${lib.escapeShellArg drmLinks.render-igpu}
            test "$(readlink ${enabled.environment.etc.render-dgpu.source})" = ${lib.escapeShellArg drmLinks.render-dgpu}
            test -e ${baseToplevel}
            test -e ${enabledToplevel}
            touch $out
          '';

      homeConfigurations = {
        "minttea@flowX13" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-unstable;
          modules = [
            niri.homeModules.niri
            aura-plugins.homeManagerModules.aura-config-sync
            ./modules/home-manager
            ./programs/neovim
            ./users/minttea/home.nix
            ./users/minttea/home.flowX13.nix
          ];
          extraSpecialArgs = extraSpecialArgs // {
            GLOBALS.hostName = "flowX13";
            GLOBALS.theme = {
              name = "balcony";
              basePath = ./packages/themes/balcony;
            };
          };
        };

        "minttea@desktop" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-unstable;
          modules = [
            niri.homeModules.niri
            aura-plugins.homeManagerModules.aura-config-sync
            #aura-plugins.homeManagerModules.temporal-service
            #aura-plugins.homeManagerModules.aurad-service
            ./modules/home-manager
            ./programs/neovim
            ./users/minttea/home.nix
            ./users/minttea/home.desktop.nix
            {
              CUSTOM.games.minecraft.enable = false;
              programs.lutris.enable = true;
            }
          ];
          extraSpecialArgs = extraSpecialArgs // {
            GLOBALS.hostName = "desktop";
            GLOBALS.theme = {
              name = "balcony";
              basePath = ./packages/themes/balcony;
            };
          };
        };

        "minttea@wsl" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-unstable;
          modules = [
            niri.homeModules.niri
            aura-plugins.homeManagerModules.aura-config-sync
            ./modules/home-manager
            ./programs/neovim
            ./users/minttea/wsl.nix
          ];
          extraSpecialArgs = extraSpecialArgs // {
            GLOBALS.hostName = "wsl";
            GLOBALS.theme = {
              name = "balcony";
              basePath = ./packages/themes/balcony;
            };
          };
        };
        "minttea@flowX13-wsl" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgs-unstable;
          modules = [
            niri.homeModules.niri
            aura-plugins.homeManagerModules.aura-config-sync
            ./modules/home-manager
            ./programs/neovim
            ./users/minttea/wsl.nix
          ];
          extraSpecialArgs = extraSpecialArgs // {
            GLOBALS.hostName = "flowX13-wsl";
            GLOBALS.theme = {
              name = "balcony";
              basePath = ./packages/themes/balcony;
            };
          };
        };
      };


      homeModules = {
        default = (
          args@{ config
          , lib ? config.lib
          , pkgs
          , ...
          }:
          {
            imports = [
              ./modules/home-manager
            ];
          }
        );
      };
    };
}
