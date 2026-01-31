{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.virtualisation.llm-sandbox;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    types
    ;

  # Capture values for use in guest config (avoid closure issues)
  vmVcpu = cfg.vm.vcpu;
  vmMem = cfg.vm.mem;
  workspaceHostPath = cfg.workspace.hostPath;
  vsockCid = cfg.vsock.cid;

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

  config = mkIf cfg.enable {
    # Ensure workspace directory exists on host
    systemd.tmpfiles.rules = [
      "d ${workspaceHostPath} 0755 root root -"
    ];

    # Configure microvm for llm-sandbox
    microvm.vms.llm-sandbox = {
      # Allow the VM to inherit overlays for claude-code
      inherit pkgs pkgs-unstable;

      # Inline guest NixOS configuration
      config = { config, pkgs, lib, ... }: {
        # System identification
        system.stateVersion = "25.11";
        networking.hostName = "llm-sandbox";

        # No TCP/IP networking - only VSOCK communication
        networking.useDHCP = false;
        networking.firewall.enable = false;

        # Disable unnecessary services
        services.openssh.enable = false;

        # LLM agent user
        users.users.agent = {
          isNormalUser = true;
          home = "/home/agent";
          description = "LLM Agent User";
          extraGroups = [ "wheel" ];
        };

        # Passwordless sudo for agent (sandbox is isolated)
        security.sudo.wheelNeedsPassword = false;

        # Guest packages for LLM agent development
        environment.systemPackages = with pkgs; [
          # LLM tooling (from llm-agents overlay)
          claude-code

          # Terminal multiplexer
          tmux

          # Programming languages/runtimes
          python3
          nodejs

          # Development tools
          git
          curl
          jq
          ripgrep

          # Essential utilities
          coreutils
          gnugrep
          gnused
          gawk
          findutils
          which
          file
          less
          tree

          # Editor
          neovim
        ];

        # Enable nix for the agent
        nix.settings.experimental-features = [ "nix-command" "flakes" ];

        # Console configuration - auto-login as agent
        services.getty.autologinUser = "agent";

        # Environment variables
        environment.variables = {
          WORKSPACE = "/workspace";
        };

        # Shell configuration
        programs.bash.enable = true;
        environment.interactiveShellInit = ''
          cd /workspace 2>/dev/null || true
        '';

        # microvm guest-specific configuration
        microvm = {
          # Hypervisor selection
          hypervisor = "qemu";

          # Resource allocation
          vcpu = vmVcpu;
          mem = vmMem;

          # virtio-fs share for workspace
          shares = [
            {
              tag = "workspace";
              source = workspaceHostPath;
              mountPoint = "/workspace";
              proto = "virtiofs";
            }
          ];

          # VSOCK for host-guest communication (no TCP/IP)
          vsock = {
            cid = vsockCid;
          };

          # No network interfaces - isolated sandbox
          interfaces = [ ];

          # Use virtiofs for /nix/store as well (read-only)
          writableStoreOverlay = null;
        };

        # Mount workspace via virtio-fs
        fileSystems."/workspace" = {
          device = "workspace";
          fsType = "virtiofs";
        };
      };
    };

    # Enable the microvm host module
    microvm.host.enable = true;
  };
}
