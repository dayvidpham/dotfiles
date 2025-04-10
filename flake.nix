{
  description = "Base configuration using flake to manage NixOS";

  # Inputs
  # https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    #############################
    # NixOS-related inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixpkgs-wsl.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    #############################
    # Nix package management
    nix-multithreaded.url = "github:DeterminateSystems/nix-src/multithreaded-eval";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    home-manager-wsl = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs-wsl";
    };

    #############################
    # Community tools
    nil-lsp = {
      url = "github:oxalica/nil";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    #############################
    # Other software
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.nixpkgs-stable.follows = "nixpkgs-stable";
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
    , determinate
    , nix-multithreaded
    , home-manager
    , home-manager-wsl
      # Community tools
    , nil-lsp
    , niri
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
          #nix-multithreaded.overlays.default
          #nix.overlays.default

          # NOTE: My own packages and programs
          (final: prev: {
            run-cwd = with prev; callPackage ./packages/run-cwd.nix { };
            scythe = with prev; callPackage ./packages/scythe.nix {
              wl-clipboard = wl-clipboard-rs;
              output-dir = "$HOME/Pictures/scythe";
            };
            waybar-balcony = with prev; callPackage ./packages/themes/balcony/waybar {
              rofi = rofi-wayland-unwrapped;
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

      # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
      noChannelModule = {
        #nix.package = nix.packages."${system}".nix;

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
          ;
      };

      extraSpecialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          nil-lsp
          niri
          ;
      };
    in
    {
      # Used with `nixos-rebuild --flake .#<hostname>`
      # nixosConfigurations."<hostname>".config.system.build.toplevel must be a derivation
      nixosConfigurations = {
        flowX13 = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          modules = [
            determinate.nixosModules.default
            niri.nixosModules.niri
            ./modules/nixos
            noChannelModule
            ./hosts/flowX13/configuration.nix
          ];
        };

        desktop = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          modules = [
            determinate.nixosModules.default
            niri.nixosModules.niri
            ./modules/nixos
            noChannelModule
            ./hosts/desktop/configuration.nix
          ];
        };

        wsl = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          #specialArgs = specialArgs // {
          #  pkgs = pkgs-wsl;
          #};
          modules = [
            determinate.nixosModules.default
            niri.nixosModules.niri
            (nixos-wsl.nixosModules.default // {
              system.build.installBootLoader = lib.mkForce "${pkgs.coreutils}/bin/true";
            })
            noChannelModule
            ./hosts/wsl/configuration.nix
            ./modules/nixos
          ];
        };
        flowX13-wsl = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          modules = [
            (nixos-wsl.nixosModules.default // {
              system.build.installBootLoader = lib.mkForce "${pkgs.coreutils}/bin/true";
            })
            ./hosts/flowX13-wsl/configuration.nix
            ./modules/nixos
            noChannelModule
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
            {
              CUSTOM.games.minecraft.enable = true;
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
