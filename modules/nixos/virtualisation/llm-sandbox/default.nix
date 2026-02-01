# LLM Sandbox Host Configuration
# This module configures the host to run the llm-sandbox microVM.
# The guest configuration is defined in ./guest.nix
{ config
, options
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.llm-sandbox;
  hasMicrovm = options ? microvm;

  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkEnableOption
    optionalAttrs
    types
    ;
in
{
  options.CUSTOM.virtualisation.llm-sandbox = {
    enable = mkEnableOption "LLM agent sandbox microVM";

    vm = {
      vcpu = mkOption {
        type = types.int;
        default = 2;
        description = "Number of virtual CPUs for the sandbox VM";
        example = 4;
      };

      mem = mkOption {
        type = types.int;
        default = 4096 * 2;
        description = "Memory allocation in MiB for the sandbox VM";
        example = 4096;
      };
    };

    workspace = {
      hostPath = mkOption {
        type = types.str;
        default = "/var/lib/llm-sandbox/workspace";
        description = "Host path to share with the sandbox VM via virtio-fs";
        example = "/home/user/llm-workspace";
      };
    };

    vsock = {
      cid = mkOption {
        type = types.int;
        default = 3;
        description = "VSOCK Context ID for host-guest communication";
        example = 100;
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Host-side config (works without microvm module)
    {
      systemd.tmpfiles.rules = [
        "d ${cfg.workspace.hostPath} 0755 root root -"
      ];

      # Web console for llm-sandbox via ttyd
      # Access at: http://localhost:7681
      # Binds to localhost only, bridges WebSocket to VSOCK
      systemd.services.llm-sandbox-console = {
        description = "LLM Sandbox Web Console";
        wantedBy = [ "multi-user.target" ];
        after = [ "microvm@llm-sandbox.service" ];
        bindsTo = [ "microvm@llm-sandbox.service" ];
        serviceConfig = {
          Type = "simple";
          DynamicUser = true;
          ExecStart = "${pkgs.ttyd}/bin/ttyd -i 127.0.0.1 -p 7681 -W ${pkgs.socat}/bin/socat - VSOCK-CONNECT:${toString cfg.vsock.cid}:5000";
          Restart = "on-failure";
          RestartSec = "5s";
          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
        };
      };
    }

    # microvm-specific config (only when microvm module is available)
    (optionalAttrs hasMicrovm {
      microvm.vms.llm-sandbox = {
        inherit pkgs;

        config = { ... }: {
          imports = [ ./guest.nix ];

          CUSTOM.virtualisation.llm-sandbox.guest = {
            vcpu = cfg.vm.vcpu;
            mem = cfg.vm.mem;
            workspace.hostPath = cfg.workspace.hostPath;
            vsock.cid = cfg.vsock.cid;
          };
        };
      };

      microvm.host.enable = true;
    })
  ]);
}
