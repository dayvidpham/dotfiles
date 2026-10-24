{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.clip-tunnel;
  inherit (lib) mkEnableOption mkIf mkOption types;
  tunnel = pkgs.writeShellApplication {
    name = "clip-tunnel";
    text = ''
      # systemd expands the local socket's %t before passing it as argv[1].
      # This foreground process is owned ONLY by clip-tunnel.service, not viewers.
      exec ${lib.getExe' cfg.sshPackage "ssh"} -n -N -T -S none \
        -o ControlMaster=no -o ControlPersist=no \
        -o ForkAfterAuthentication=no -o BatchMode=yes \
        -o StrictHostKeyChecking=yes -o ExitOnForwardFailure=yes \
        -o ConnectTimeout=10 -o ConnectionAttempts=1 \
        -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
        -R ${lib.escapeShellArg cfg.remoteSocketPath}:"$1" \
        -- ${lib.escapeShellArg cfg.host}
    '';
  };
in
{
  options.CUSTOM.services.clip-tunnel = {
    enable = mkEnableOption "graphical-session-owned clipboard SSH tunnel (independent of VNC and Moonlight)";
    host = mkOption {
      type = types.strMatching "[^[:space:]%]+";
      default = "desktop";
      description = ''
        SSH destination running clip-sync. Clipboard sync stays connected to this
        host throughout the graphical session, even with no viewer or while
        viewing another host. Disable this service to opt out of that sharing.
        Provision a verified known-host entry and a usable key/agent first:
        authentication and host-key failures are journaled and retried without prompts.
      '';
    };
    socketPath = mkOption {
      type = types.strMatching "(/[a-zA-Z0-9_./@+-]+|%t/[a-zA-Z0-9_./@+-]+)";
      default = config.CUSTOM.services.clipd.socketPath;
      description = "Local clipd socket; systemd expands %t to the user runtime directory.";
    };
    remoteSocketPath = mkOption {
      type = types.strMatching "/[a-zA-Z0-9_./@+-]+";
      default = "/run/user/1000/clipd.sock";
      description = "Absolute socket on the SSH host consumed by clip-sync; use that host's user UID.";
    };
    systemdTarget = mkOption {
      type = types.str;
      default = config.CUSTOM.services.clipd.systemdTarget;
      description = "Graphical session target owning both clipd and this singleton tunnel.";
    };
    sshPackage = mkOption {
      type = types.package;
      default = pkgs.openssh;
      description = "Package providing ssh for the foreground clipboard transport.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.CUSTOM.services.clipd.enable;
        message = "CUSTOM.services.clip-tunnel requires CUSTOM.services.clipd.enable = true to serve the graphical clipboard.";
      }
      {
        assertion = cfg.systemdTarget == config.CUSTOM.services.clipd.systemdTarget;
        message = "clip-tunnel.systemdTarget must match clipd.systemdTarget so both stop with the same graphical session.";
      }
    ];
    systemd.user.services.clip-tunnel = {
      Unit = {
        Description = "Clipboard tunnel to ${cfg.host} (viewer-independent; see journal for SSH/key failures)";
        Documentation = [ "man:ssh(1)" ];
        PartOf = [ cfg.systemdTarget ];
        # Pull in the producer, but keep the forward alive across its restarts.
        # A Requires stop would strand this consumer after clipd recovers.
        Wants = [ "clipd.service" ];
        After = [ cfg.systemdTarget "clipd.service" ];
        # Recover after network/authentication repairs, but never spin rapidly.
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = lib.escapeShellArgs [ (lib.getExe tunnel) cfg.socketPath ];
        Restart = "always";
        RestartSec = 5;
        TimeoutStartSec = 15;
        TimeoutStopSec = 10;
      };
      Install.WantedBy = [ cfg.systemdTarget ];
    };
  };
}
