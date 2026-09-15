{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.services.github-runner;

  inherit (lib)
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    mkOption
    types
    ;

  # Kept clear of the subid ranges used by minttea and gitlab-runner
  # (100000-265534) and the openclaw instances (300000-431071).
  subIdStart = 500000;
  subIdCount = 65536;

  podman = config.virtualisation.podman.package;

  # `virtualisation.podman.dockerCompat` only installs the `docker` shim into
  # the system profile, which systemd services do not inherit.
  dockerShim = pkgs.runCommand "docker-podman-shim" { } ''
    mkdir -p $out/bin
    ln -s ${podman}/bin/podman $out/bin/docker
  '';

  # The nixpkgs module provides bash, coreutils, git, tar, gzip and nix;
  # jobs expect a normal Linux command set on top of that.
  basePackages = with pkgs; [
    curl
    diffutils
    file
    findutils
    gawk
    gnugrep
    gnused
    jq
    less
    openssh
    procps
    psmisc
    unzip
    which
    xz
    zip
    zstd
  ];

  runnerNames = map (i: "${cfg.name}-${toString i}") (lib.range 1 cfg.count);

  workDirFor = name: "${cfg.workDir}/${name}";

  mkRunner = runnerName: {
    enable = true;
    url = cfg.url;
    name = runnerName;
    replace = true;
    inherit (cfg) ephemeral runnerGroup tokenFile;
    extraLabels = cfg.labels;
    user = cfg.user.name;
    group = cfg.user.name;
    workDir = workDirFor runnerName;
    extraEnvironment = {
      # systemd services do not inherit the interactive shell CA setup.
      SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      CURL_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    } // lib.optionalAttrs cfg.podman.enable {
      # Jobs talk to the runner user's rootless podman socket, never the
      # root-equivalent system socket.
      DOCKER_HOST = "unix:///run/user/${toString cfg.user.uid}/podman/podman.sock";
    } // cfg.extraEnvironment;
    extraPackages = basePackages ++ cfg.extraPackages
      ++ lib.optional cfg.podman.enable podman
      ++ lib.optional cfg.podman.enable dockerShim;
    serviceOverrides = {
      # The job workspace must exist before systemd sets up the mount
      # namespace for the unit's BindPaths. StateDirectory is created by
      # systemd on every unit start; a tmpfiles rule would not be applied
      # on the first nixos-rebuild switch.
      StateDirectory = mkForce [
        "github-runner/${runnerName}"
        (lib.removePrefix "/var/lib/" (workDirFor runnerName))
      ];
    } // lib.optionalAttrs cfg.podman.enable {
      # Rootless podman needs real user/network namespaces, the setuid
      # newuidmap/newgidmap helpers, and its per-user socket under /run/user.
      PrivateUsers = false;
      RestrictNamespaces = false;
      NoNewPrivileges = false;
      ProtectHome = false;
      PrivateDevices = false; # /dev/fuse, /dev/net/tun for podman storage/network
      # The upstream deny list is aimed at plain services; podman needs
      # mount/unshare/pivot_root.
      SystemCallFilter = mkForce [ ];
      # The upstream "optimizations" neutralize the setuid newuidmap/newgidmap
      # helpers and drop all capabilities, which rootless podman requires.
      RestrictSUIDSGID = false;
      AmbientCapabilities = mkForce [ ];
      CapabilityBoundingSet = mkForce [ ];
      DeviceAllow = mkForce [ ];
    } // cfg.serviceOverrides;
  };
in
{
  options.CUSTOM.services.github-runner = {
    enable = mkEnableOption "GitHub Actions self-hosted runner";

    url = mkOption {
      type = types.str;
      default = "https://github.com/peasant-labs";
      description = "GitHub organization (or repository) the runner registers against";
    };

    name = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Base runner name; instances are suffixed -1..count";
    };

    count = mkOption {
      type = types.int;
      default = 1;
      description = "Runner instances to run; each handles one job at a time";
    };

    labels = mkOption {
      type = types.listOf types.str;
      default = [ "nixos" "podman" ];
      description = "Extra labels on top of the default self-hosted/linux/x64 labels";
    };

    runnerGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Organization runner group. Must already exist in GitHub before the
        service starts, otherwise registration fails.
      '';
    };

    ephemeral = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Register per job and wipe runner state afterwards. Requires a
        fine-grained PAT in {option}`tokenFile`.
      '';
    };

    tokenFile = mkOption {
      type = types.path;
      description = ''
        File containing a fine-grained PAT with organization "Self-hosted
        runners: Read and write" permission (or a classic admin:org PAT).
      '';
      example = "/run/secrets/github-runner/token";
    };

    user.name = mkOption {
      type = types.str;
      default = "github-runner";
      description = "System user the runner and its jobs run as";
    };

    user.uid = mkOption {
      type = types.int;
      default = 981;
      description = "UID for the runner user";
    };

    workDir = mkOption {
      type = types.str;
      default = "/var/lib/github-runner/work";
      description = "Parent directory for per-instance job workspaces";
    };

    nixAccess.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Allow the runner user to talk to the Nix daemon (nix.settings.allowed-users)";
    };

    podman.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Rootless podman access for jobs, via a docker-compatible socket";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages on the runner's PATH";
    };

    extraEnvironment = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional environment variables for the runner service";
    };

    serviceOverrides = mkOption {
      type = types.attrs;
      default = { };
      description = "systemd service overrides, merged last (see services.github-runners)";
    };

    sudoInto = {
      enable = mkEnableOption "passwordless sudo login to the runner user for debugging";
      fromUser = mkOption {
        type = types.str;
        default = null;
        description = "User allowed to call sudo -u <runner> -i without a password";
        example = "minttea";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/var/lib/" cfg.workDir;
        message = "CUSTOM.services.github-runner.workDir must live under /var/lib so systemd can create it as a state directory before setting up the unit's mount namespace";
      }
    ];

    CUSTOM.virtualisation.podman.enable = mkIf cfg.podman.enable true;

    security.polkit.enable = mkDefault true; # Required for linger

    users.groups.${cfg.user.name} = { };

    users.extraUsers.${cfg.user.name} = {
      name = cfg.user.name;
      group = cfg.user.name;
      description = "For GitHub Actions runners";
      uid = cfg.user.uid;
      isNormalUser = false;
      isSystemUser = true;
      createHome = true;
      home = "/var/lib/${cfg.user.name}";
      homeMode = "0770";
      linger = true; # NOTE: requires security.polkit.enable = true
      subUidRanges = [
        {
          startUid = subIdStart;
          count = subIdCount;
        }
      ];
      subGidRanges = [
        {
          startGid = subIdStart;
          count = subIdCount;
        }
      ];
    };

    services.github-runners = lib.genAttrs runnerNames mkRunner;

    nix.settings.allowed-users = mkIf cfg.nixAccess.enable [ cfg.user.name ];

    security.sudo = mkIf cfg.sudoInto.enable {
      enable = true;
      extraRules = [
        {
          users = [ cfg.sudoInto.fromUser ];
          runAs = cfg.user.name;
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" "SETENV" ];
            }
          ];
        }
      ];
    };
  };
}
