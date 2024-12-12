{ config
, pkgs
, ...
}:

{
  imports = [
    ./v4l2loopback
    ./services
    ./desktops
    ./hardware
    ./fonts
    ./programs
  ];

  config = {
    environment.variables = {
      HOST = config.networking.hostName;
    };

    nix.settings.substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    nix.settings.trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];

    # to allow flashing of keyboard
    services.udev.packages = with pkgs; [ vial via ];
  };
}
