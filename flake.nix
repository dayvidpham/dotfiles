{
  description = "Base configuration using flake to manage NixOS";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" "fetch-closure" ];
    substituters = [
      "https://cache.nixos.org"
    ];
    extra-substituters = [
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # Inputs
  # https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    # The master branch of the NixOS/nixpkgs repository on GitHub.
    # inputs.unstable.url = "github:NixOS/nixpkgs/master";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-multithreaded.url = "github:DeterminateSystems/nix-src/multithreaded-eval";
    nix = {
      url = "github:NixOS/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nil-lsp = {
      url = "github:oxalica/nil";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , nix
    , nix-multithreaded
    , flake-registry
    , home-manager
    , nil-lsp
    , nixos-wsl
    , ...
    }:
    let
      system = "x86_64-linux";
      nixpkgs-options = {
        inherit system;

        config = {
          allowUnfree = true;
          cudaSuport = true;
        };

        overlays = [
          #nix-multithreaded.overlays.default
          nix.overlays.default

          # NOTE: My own packages and programs
          (final: prev: {
            run-cwd = with final; callPackage ./packages/run-cwd.nix { };
            scythe = with final; callPackage ./packages/scythe.nix {
              wl-clipboard = wl-clipboard-rs;
              output-dir = "$HOME/Pictures/scythe";
            };
            waybar-balcony = with final; callPackage ./packages/themes/balcony/waybar {
              rofi = rofi-wayland-unwrapped;
            };
          })
        ];
      };

      pkgs = import nixpkgs nixpkgs-options;
      pkgs-unstable = import nixpkgs-unstable nixpkgs-options;

      lib = pkgs.lib;

      # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
      noChannelModule = {
        nix.package = pkgs.nix;

        nix.settings.experimental-features = [ "nix-command" "flakes" "fetch-closure" ];
        nix.channel.enable = false;

        nix.registry.nixpkgs.flake = nixpkgs;
        nix.registry.home-manager.flake = home-manager;
        nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;
        environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
        environment.etc."nix/inputs/home-manager".source = "${home-manager}";

        nix.nixPath = lib.mkForce [
          "nixpkgs=/etc/nix/inputs/nixpkgs"
          "home-manager=/etc/nix/inputs/home-manager"
        ];
        nix.settings.nix-path = lib.mkForce [
          "nixpkgs=/etc/nix/inputs/nixpkgs"
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
          pkgs
          pkgs-unstable
          libmint
          ;
      };

      extraSpecialArgs = {
        inherit
          pkgs-unstable
          nil-lsp
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
            ./hosts/flowX13/configuration.nix
            ./modules/nixos
            noChannelModule
          ];
        };

        desktop = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          modules = [
            ./hosts/desktop/configuration.nix
            ./modules/nixos
            noChannelModule
          ];
        };

        wsl = nixpkgs.lib.nixosSystem {
          inherit
            system
            specialArgs
            ;
          modules = [
            nixos-wsl.nixosModules.default
            ./hosts/wsl/configuration.nix
            ./modules/nixos
            noChannelModule
          ];
        };
      };

      homeConfigurations = {
        "minttea@flowX13" = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
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
            ./modules/home-manager
            ./programs/neovim
            ./users/minttea/home.nix
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
    };
}
