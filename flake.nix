{
  description = "Base configuration using flake to manage NixOS";

  # Inputs
  # https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html#flake-inputs

  # The master branch of the NixOS/nixpkgs repository on GitHub.
  # inputs.unstable.url = "github:NixOS/nixpkgs/master";

  inputs = {
    nixpkgs.url = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.url = "github:hyprwm/Hyprland";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, hyprland, ... }: 
  let
    lib = nixpkgs.lib;
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # Used with `nixos-rebuild --flake .#<hostname>`
    # nixosConfigurations."<hostname>".config.system.build.toplevel must be a derivation
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ ./configuration.nix ] ;
    };
    
    homeConfigurations = {
      dhpham = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ 
          ./home.nix
          hyprland.homeManagerModules.default
          { wayland.windowManager.hyprland.enable = true; }
        ];
      };
    };
  };
}
