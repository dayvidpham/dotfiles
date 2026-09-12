{ config
, pkgs
, lib
, ...
}:
let
  cfg = config.CUSTOM.clipboardTunnel;

  inherit (lib)
    mkIf
    mkEnableOption
    mkOption
    types
    getExe
    ;

  # Sway, headless: a clipboard owner that exists whether or not the
  # interactive session is running. Its socket must be deterministic, but sway
  # 1.12 has no --socket flag and wl_display_add_socket_auto just takes the
  # lowest free name, so we give it a *dedicated* XDG_RUNTIME_DIR in which the
  # first free name is always wayland-1, and we clear stale sockets first.
  #
  # Caveat: this compositor's clipboard is separate from the interactive
  # session's. It serves headless/remote workflows and GUI apps that live in
  # this compositor; it does not populate niri's/wayland-1 clipboard.
  swayConfig = pkgs.writeText "sway-clip.conf" ''
    # Intentionally minimal: no inputs, no bar, no keybindings.
  '';

  compositorWrapper = pkgs.writeShellApplication {
    name = "clip-compositor";
    runtimeInputs = [ pkgs.iproute2 pkgs.gnugrep ];
    text = ''
      set -eu
      sock="''${XDG_RUNTIME_DIR}/''${WAYLAND_DISPLAY}"
      if [ -e "$sock" ] && ! ss -xl | grep -qF " $sock"; then
        rm -f "$sock" "$sock.lock"
      fi
      exec ${pkgs.sway}/bin/sway -c ${swayConfig}
    '';
  };

  clip = pkgs.writeShellApplication {
    name = "clip";
    runtimeInputs = [ pkgs.python3 pkgs.wl-clipboard ];
    text = ''
      exec python3 ${./py}/clip.py "$@"
    '';
  };

  clipSync = pkgs.writeShellApplication {
    name = "clip-sync";
    runtimeInputs = [ pkgs.python3 pkgs.wl-clipboard ];
    text = ''
      exec python3 ${./py}/clip-sync.py "$@"
    '';
  };
in
{
  options.CUSTOM.clipboardTunnel = {
    enable = mkEnableOption "headless clipboard compositor + peer clipboard tunnel client";

    user = mkOption {
      type = types.str;
      description = "User running the headless compositor and sync";
      example = "minttea";
    };

    display = mkOption {
      type = types.str;
      default = "wayland-1";
      description = "WAYLAND_DISPLAY of the headless compositor (always 1: it gets a dedicated runtime dir)";
    };

    compositorRuntimeDir = mkOption {
      type = types.str;
      default = "/run/user/1000/clip";
      description = ''
        Dedicated XDG_RUNTIME_DIR for the headless compositor. Kept separate so
        sway's auto-picked socket name is deterministic (wayland-1).
      '';
    };

    socketPath = mkOption {
      type = types.str;
      default = "/run/user/1000/clipd.sock";
      description = "Peer clipd socket, provided by an ssh RemoteForward";
    };

    syncInterval = mkOption {
      type = types.float;
      default = 1.0;
      description = "Seconds between peer clipboard polls";
    };
  };

  config = mkIf cfg.enable {
    # NOTE: do NOT set WAYLAND_DISPLAY globally here — the interactive session
    # owns its own value (niri's wayland-1). Only the services below point at
    # the headless compositor, via their own Environment=.
    environment.systemPackages = [ clip clipSync ];

    systemd.services.clip-compositor = {
      description = "Headless sway clipboard compositor for ${cfg.user}";
      documentation = [ "man:sway(1)" ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        # Dedicated runtime dir (inside the user's) so sway's auto socket name
        # is deterministic; created here because it is not a system /run path.
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p -m 0700 ${cfg.compositorRuntimeDir}";
        # sway's wrapper adds --unsupported-gpu; the headless backend needs no GPU.
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.compositorRuntimeDir}"
          "WLR_BACKENDS=headless"
          "WLR_RENDERER=pixman"
          "WLR_LIBINPUT_NO_DEVICES=1"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
        ];
        ExecStart = "${getExe compositorWrapper}";
        ExecStop = "-${pkgs.sway}/bin/swaymsg -s ${cfg.compositorRuntimeDir}/${cfg.display} exit";
        Restart = "always";
        RestartSec = 2;
      };
    };

    systemd.services.clip-sync = {
      description = "Mirror peer clipboard into the headless compositor";
      after = [ "clip-compositor.service" ];
      requires = [ "clip-compositor.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = "users";
        Environment = [
          "XDG_RUNTIME_DIR=${cfg.compositorRuntimeDir}"
          "WAYLAND_DISPLAY=${cfg.display}"
          "HOME=/home/${cfg.user}"
        ];
        ExecStart = "${getExe clipSync} ${cfg.socketPath} ${toString cfg.syncInterval}";
        Restart = "always";
        RestartSec = 3;
      };
    };
  };
}
