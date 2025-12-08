{ config
, pkgs
, lib
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
    ./shared
    ./virtualisation
    ./generate
  ];

  config = {
    environment.variables = {
      HOST = config.networking.hostName;
    };

    nix.settings.trusted-substituters = [
      "https://cache.nixos.org?priority=1"
      "https://nix-community.cachix.org?priority=2"
      "https://cuda-maintainers.cachix.org?priority=3"
    ];
    nix.settings.trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
    nix.settings.builders-use-substitutes = lib.mkDefault true;
    nix.settings.always-allow-substitutes = lib.mkDefault false;

    # Performance boosts: enable higher number of parallel binary cache pulls
    nix.settings.http-connections = lib.mkDefault 128;
    nix.settings.max-substitution-jobs = lib.mkDefault 128;
    nix.settings.download-buffer-size = 1024;

    # Fall back to other substituter
    nix.settings.fallback = true;

    # Fail fast
    nix.settings.connect-timeout = 5;
  };
}
