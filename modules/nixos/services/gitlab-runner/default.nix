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
      homeMode = "0770";
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
        # INFO: Maps the host user (gitlab-runner) to UID 0 (root) inside the container.
        "--userns=keep-id"
        # INFO: Runs command inside container as root
        "--user=root"
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

    systemd.tmpfiles.rules = [
      #  Type  Path                             Mode    Owner            Group            Age  Argument
      "d       /var/lib/gitlab-runner/config    0770    gitlab-runner    gitlab-runner    -    -"
    ];

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
