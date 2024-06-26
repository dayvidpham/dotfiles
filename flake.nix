{
  description = "Base configuration using flake to manage NixOS";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" "repl-flake" ];
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

    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nil-lsp = {
      url = "github:oxalica/nil";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , flake-registry
    , home-manager
    , nil-lsp
    , ...
    }:
    let
      system = "x86_64-linux";

      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = (_: true);
        };
        overlays = [
          (final: prev: {
            # NOTE: My own packages and programs
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

      lib = pkgs.lib;

      # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
      noChannelModule = {
        nix.channel.enable = false;

        nix.registry.nixpkgs.flake = nixpkgs;
        nix.registry.home-manager.flake = home-manager;
        environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
        environment.etc."nix/inputs/home-manager".source = "${home-manager}";

        nix.settings.nix-path = lib.mkForce [
          "nixpkgs=/etc/nix/inputs/nixpkgs"
          "home-manager=/etc/nix/inputs/home-manager"
        ];
        nix.settings.flake-registry = "${flake-registry}/flake-registry.json";
      };

      # NOTE: Utils and enum types
      libmint =
        import ./modules/nixos/libmint.nix { inherit lib; };

      # NOTE: Common args to be passed to nixosConfigs and homeConfigurations
      specialArgs = {
        inherit
          pkgs
          libmint
          ;
      };

      extraSpecialArgs = {
        inherit
          nil-lsp
          ;
        inherit (pkgs)
          run-cwd
          scythe
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
      };
    };
}
