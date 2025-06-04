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

in
{
  options.CUSTOM.setup.gitlab-runner-podman = {
    enable = mkEnableOption "Adds and configures gitlab-runner user, and enables podman";
  };

  config = mkIf cfg.enable {
    ###############
    # Podman setup, to be used by default

    CUSTOM.virtualisation.podman.enable = true;

    ###############
    # User setup

    security.polkit.enable = true;

    users.extraUsers.gitlab-runner = {
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
      name = "gitlab-runner";
      group = "gitlab-runner";
      extraGroups = [ "network" ];
      description = "For the GitLab Runner";
    };
    users.extraGroups.gitlab-runner = { };


  };
}
