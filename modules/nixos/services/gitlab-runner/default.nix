{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.gitlab-runner;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

  runnerUid = 980;

  podman = "${config.virtualisation.podman.package}/bin/podman";
in
{
  options.CUSTOM.services.gitlab-runner = {
    enable = mkEnableOption "Adds and configures gitlab-runner user, and enables podman";
    user.uid = lib.mkOption {
      type = lib.types.int;
      default = runnerUid;
      description = "the uid of the gitlab-runner account";
      example = "980 (below 1000 typical for system services)";
    };

    sudoInto = {
      enable = mkEnableOption "Allows the user {option}sudoerUser to call sudo -u gitlab-runner -i without password";
      fromUser = mkOption {
        type = lib.types.str;
        default = null;
        description = "the user that can call sudo and login to gitlab-runner without password";
        example = "minttea";
      };
    };
  };

  config = mkIf cfg.enable {
    ###############
    # Podman setup, to be used by default

    CUSTOM.virtualisation.podman.enable = true;

    ###############
    # User setup

    security.polkit.enable = true;

    users.extraUsers.gitlab-runner = {
      name = "gitlab-runner";
      group = "gitlab-runner";
      extraGroups = [ "network" ];
      description = "For the GitLab Runner";
      uid = cfg.user.uid;
      isNormalUser = false;
      isSystemUser = true;
      createHome = true;
      home = "/var/lib/gitlab-runner";
      linger = true; # NOTE: requires security.polkit.enable = true
      subUidRanges = [
        {
          startUid = 100000;
          count = 165535;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 165535;
        }
      ];
    };
    users.groups.gitlab-runner = { };

    virtualisation.oci-containers.containers.gitlab-runner = {
      # This runs the container via the rootless Podman instance of the 'gitlab-runner' user.
      user = "gitlab-runner";
      image = "gitlab/gitlab-runner:latest";
      # Restart the container if it stops.
      autoStart = true;
      extraOptions = [
        # CRITICAL: Maps the host user (gitlab-runner) to UID 0 (root) inside the container.
        "--userns=keep-id"
      ];
      volumes = [
        # Persist the runner's config.toml on the host.
        "/var/lib/gitlab-runner/config:/etc/gitlab-runner:Z"
        # The key to "Docker-in-Docker": Mount the host's rootless Podman socket
        # to the default Docker socket location inside the runner container.
        # This simplifies the config.toml significantly.
        "/run/user/${toString cfg.user.uid}/podman/podman.sock:/var/run/docker.sock:Z"
      ];
    };
    systemd.user.services.sfurs-gitlab-runner = {
      enable = true;
      # Run the service as the gitlab-runner user
      wantedBy = [ "podman.socket" ];
      after = [ "podman.socket" ];
      requisite = [ "podman.socket" ];

      #requisite = [ "network-online.target" ];
      #bindsTo = [ "network-online.target" ];

      unitConfig = {
        ConditionUser = "gitlab-runner";
      };

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = "5s";

        ExecStartPre = (if config.networking.networkmanager.enable then
          let
            nm-online = "${config.networking.networkmanager.package}/bin/nm-online";
          in
          ''
            ${nm-online} -s
          ''
        else
          let
            # assume using networkd
            networkctl = "${pkgs.systemd}/bin/networkctl";
          in
          ''
            ${networkctl} wait-online
          ''
        );

        ExecStart = ''
          ${podman} run --name sfurs --restart=always --replace \
            --user root \
            -v "%t/podman/podman.sock:/var/run/podman/podman.sock" \
            -v gitlab-runner-config:/etc/gitlab-runner \
            gitlab/gitlab-runner:latest
        '';
      };
    };

    security.sudo = mkIf (cfg.sudoInto.enable) {
      enable = true; # Ensure sudo is enabled (usually is by default if you have users)
      extraRules = [
        {
          users = [ cfg.sudoInto.fromUser ]; # The user who can sudo in
          runAs = "gitlab-runner"; # The target user
          commands = [
            {
              command = "ALL"; # Allows running any command as gitlab-runner
              options = [ "NOPASSWD" "SETENV" ]; # No password, allow setting environment
            }
          ];
        }
      ];
    };
  };
}
