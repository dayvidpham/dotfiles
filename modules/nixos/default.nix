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
      "https://cache.nixos-cuda.org?priority=3"
      "https://cache.numtide.com"
    ];
    # trusted-substituters only lets (unprivileged) users *request* these
    # caches; it does not enable them. Mirror the list here so the daemon
    # actually queries them (nix-community, nixos-cuda, and the
    # llm-agents cache at cache.numtide.com were all inactive).
    nix.settings.extra-substituters = [
      "https://cache.nixos.org?priority=1"
      "https://nix-community.cachix.org?priority=2"
      "https://cache.nixos-cuda.org?priority=3"
      "https://cache.numtide.com"
    ];
    nix.settings.trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
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
