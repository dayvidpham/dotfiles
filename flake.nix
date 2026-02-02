{
  description = "Base configuration using flake to manage NixOS";

  # Inputs
  # https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    #############################
    # NixOS-related inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";

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
    determinate-nixd.inputs.nix.follows = "determinate-nix";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
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
          determinate-nix.overlays.default
          llm-agents.overlays.default
          nix-openclaw.overlays.default

          # Override openclaw to disable extended tools (whisper/torch/triton)
          # Note: nodejs/pnpm excluded to avoid collision with system packages
          (final: prev: {
            openclaw = prev.openclaw.override {
              extendedTools = with final; [
                git curl jq python3 ffmpeg ripgrep
                go uv
              ];
            };
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
          sops-nix
          ;
      };

      extraSpecialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          niri
          nix-openclaw
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
        flowX13 = mkHost { name = "flowX13"; };
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
          hostSpecialArgs = { inherit pkgs pkgs-unstable nix-openclaw; };
          modules = [
            microvm.nixosModules.microvm
            ./modules/nixos/virtualisation/openclaw-vm/guest.nix
          ];
        };
      };

      homeConfigurations = {
        "minttea@flowX13" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            niri.homeModules.niri
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
          inherit pkgs;
          modules = [
            niri.homeModules.niri
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
          inherit pkgs;
          modules = [
            niri.homeModules.niri
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
          inherit pkgs;
          modules = [
            niri.homeModules.niri
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
