{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:
{
  # Native Moonlight is the default. Both the desktop launcher and moonlight-qt
  # enter a singleton user scope, stop ROC, and preserve caller environment plus
  # SDL_MOUSE_RELATIVE_SYSTEM_SCALE=1 (SDL3 via sdl2-compat) for trackpad scaling.
  CUSTOM.programs.remote-audio-client = {
    enable = true;
    moonlightPackage = pkgs-unstable.moonlight-qt;
  };

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
  # XDG_RUNTIME_DIR from niri. The desktop reads it over clip-tunnel.service.
  CUSTOM.services.clipd.enable = true;

  # One graphical-session-owned forward, shared by VNC and Moonlight. Clipboard
  # sharing with desktop continues with no viewers or while viewing ANOTHER host.
  # Set enable = false to opt out; viewing another host does not retarget sharing.
  # Pre-provision desktop's verified SSH host key and unlock the key/agent; missing
  # trust/auth fails visibly in `journalctl --user -u clip-tunnel` and retries.
  CUSTOM.services.clip-tunnel = {
    enable = true;
    host = "desktop";
    remoteSocketPath = "/run/user/1000/clipd.sock";
  };

  # Attach to the desktop's persistent sway session over VNC (tailnet-only).
  CUSTOM.programs.remote-desktop.enable = true;

  # VNC attachment alone is silent. Explicit `remote-audio-mode vnc` selects
  # ROC, deliberately closing managed Moonlight; viewer exit never restores it.
  CUSTOM.services.remote-audio = {
    enable = true;
    role = "recv";
    autostart = false;
  };
}
