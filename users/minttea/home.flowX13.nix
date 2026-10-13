{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
let
  inherit (lib)
    mkForce
    ;

  # Moonlight sends raw, unscaled relative mouse motion, so the laptop trackpad
  # (which relies on the compositor's pointer-acceleration curve) feels far too
  # fast: it never enables SDL's system scaling, and SDL3's
  # SDL_HINT_MOUSE_RELATIVE_SYSTEM_SCALE defaults to off. Export it so niri's
  # acceleration applies, while keeping relative mode (game-friendly) instead of
  # Moonlight's "optimize for remote desktop" absolute mode.
  # nixpkgs' moonlight-qt links sdl2-compat (SDL3 underneath), so the SDL3 hint
  # is read by the SDL core.
  moonlightQt = pkgs-unstable.writeShellApplication {
    name = "moonlight-qt";
    runtimeInputs = [ pkgs-unstable.moonlight-qt ];
    text = ''
      export SDL_MOUSE_RELATIVE_SYSTEM_SCALE=1
      exec moonlight-qt "$@"
    '';
  };
in
{
  # Wrapped Moonlight (see moonlightQt above). It shadows the unwrapped binary on
  # PATH, so launch with `moonlight-qt` rather than `nix run nixpkgs#moonlight-qt`.
  home.packages = [ moonlightQt ];

  # NOTE: Hyprland
  CUSTOM.wayland.windowManager.hyprland = {
    enable = false;
  };
  # NOTE: Sway, for remote desktop & waypipe
  CUSTOM.wayland.windowManager.sway = {
    enable = false;
  };

  CUSTOM.services.syncthing.enable = true;
  CUSTOM.services.syncthing.secrets = {
    enable = true;
    apiKeyFile = "/run/secrets/syncthing/apikey";
  };

  # Clipboard daemon: a user service, so it inherits WAYLAND_DISPLAY and
  # XDG_RUNTIME_DIR from niri. The desktop reads it over an ssh RemoteForward.
  CUSTOM.services.clipd.enable = true;

  # Attach to the desktop's persistent sway session over VNC (tailnet-only).
  CUSTOM.programs.remote-desktop.enable = true;

  # Receive the desktop's remote-session audio over RTP (roc) on the tailnet.
  CUSTOM.services.remote-audio = {
    enable = true;
    role = "recv";
  };
}
