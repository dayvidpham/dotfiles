{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.setup.gitlab-runner-podman;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

  runnerUid = 2000;
in
{
  options.CUSTOM.setup.gitlab-runner-podman = {
    enable = mkEnableOption "Adds and configures gitlab-runner user, and enables podman";
    user.uid = lib.mkOption {
      type = lib.types.int;
      default = runnerUid;
      description = "the uid of the gitlab-runner account";
      example = "2000 (must be between 1000 and 655534)";
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
      isNormalUser = true;
      isSystemUser = false;
      createHome = true;
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
    users.extraGroups.gitlab-runner = { };

    services.gitlab-runner = {
      enable = true;
      gracefulTermination = true;
      gracefulTimeout = "10s";

      settings = {
        concurrent = 8;
        environment = {
          FF_NETWORK_PER_BUILD = "true";
        };
      };

      services.sfurs.executor = "docker";
      services.sfurs.dockerImage = "quay.io/podman/stable";
      services.sfurs.dockerAllowedServices = [ "docker:27-dind" ];
      services.sfurs.dockerVolumes = [
        "/run/user/${toString cfg.user.uid}/podman.sock:/var/run/podman.sock"
        "/home/gitlab-runner/volumes/gitlab-runner-config:/etc/gitlab-runner"
      ];
      services.sfurs.authenticationTokenConfigFile = "/home/gitlab-runner/secrets/auth_token.env";
      services.sfurs.registrationFlags = [
        "--name dhpham-nixos-desktop"
      ];
    };
    systemd.services.gitlab-runner = {
      serviceConfig = {
        User = "gitlab-runner";
        Group = "gitlab-runner";
      };
    };
  };
}
