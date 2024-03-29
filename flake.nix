{
  description = "Base configuration using flake to manage NixOS";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
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
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ 
    self
    , nixpkgs
    , home-manager
    , nixvim
    , ... 
  }: 
  let
    lib = nixpkgs.lib;
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    # Used with `nixos-rebuild --flake .#<hostname>`
    # nixosConfigurations."<hostname>".config.system.build.toplevel must be a derivation
    nixosConfigurations = {
      vmware = nixpkgs.lib.nixosSystem {
        inherit system; 
        specialArgs = { inherit pkgs; };
        modules = [ ./hosts/vmware/configuration.nix ] ;
      };
      
      flowX13 = nixpkgs.lib.nixosSystem {
        inherit system; 
        specialArgs = { inherit pkgs; };
        modules = [ ./hosts/flowX13/configuration.nix ] ;
      };
    };
    
    homeConfigurations = {
      "dhpham@vmware" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ 
          ./users/dhpham/home.nix
        ];
        extraSpecialArgs = {
          inherit nixvim;
        };
      };

      "minttea@flowX13" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ 
          ./users/minttea/home.nix
        ];
        extraSpecialArgs = {
          inherit nixvim;
        };
      };
    };
  };
}
