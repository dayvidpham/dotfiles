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

  runnerUid = 2000;

  podman = "${config.virtualisation.podman.package}/bin/podman";
in
{
  options.CUSTOM.services.gitlab-runner = {
    enable = mkEnableOption "Adds and configures gitlab-runner user, and enables podman";
    user.uid = lib.mkOption {
      type = lib.types.int;
      default = runnerUid;
      description = "the uid of the gitlab-runner account";
      example = "2000 (must be between 1000 and 655534)";
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
