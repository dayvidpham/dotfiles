# LLM Sandbox Guest Configuration
# This module defines the NixOS configuration for the llm-sandbox microVM guest.
# It can be imported directly as a nixosConfiguration or used via microvm.vms.
{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib)
    mkOption
    mkDefault
    types
    ;

  cfg = config.CUSTOM.virtualisation.llm-sandbox.guest;
in
{
  options.CUSTOM.virtualisation.llm-sandbox.guest = {
    vcpu = mkOption {
      type = types.int;
      default = 2;
      description = "Number of virtual CPUs";
    };

    mem = mkOption {
      type = types.int;
      default = 4096 * 2;
      description = "Memory allocation in MiB";
    };

    workspace.hostPath = mkOption {
      type = types.str;
      default = "/var/lib/llm-sandbox/workspace";
      description = "Host path for workspace (used by virtio-fs)";
    };

    vsock.cid = mkOption {
      type = types.int;
      default = 3;
      description = "VSOCK Context ID";
    };
  };

  config = {
    # System identification
    system.stateVersion = "25.11";
    networking.hostName = "llm-sandbox";

    # No TCP/IP networking - only VSOCK communication
    # Firewall enabled for defense-in-depth (guards against accidental network exposure)
    networking.useDHCP = false;
    networking.firewall.enable = true;

    # Disable unnecessary services
    services.openssh.enable = false;

    # LLM agent user (unprivileged - no sudo, no root, no nix)
    users.users.agent = {
      isNormalUser = true;
      home = "/home/agent";
      description = "LLM Agent User";
    };

    # Kernel hardening
    boot.kernel.sysctl = {
      "kernel.kptr_restrict" = 2;                # Hide kernel pointers
      "kernel.dmesg_restrict" = 1;               # Restrict dmesg access
      "kernel.unprivileged_bpf_disabled" = 1;    # Disable unprivileged BPF
      "kernel.yama.ptrace_scope" = 2;            # Restrict ptrace
    };
    security.lockKernelModules = true;           # No module loading after boot

    # Guest packages for LLM agent development
    environment.systemPackages = with pkgs; [
      # LLM tooling (from llm-agents overlay)
      claude-code

      # Terminal multiplexer
      tmux

      # Programming languages/runtimes
      python3
      nodejs
      bun
      uv

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

    # Restrict nix daemon to root only (agent cannot use nix)
    nix.settings.allowed-users = [ "root" ];

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
      vcpu = cfg.vcpu;
      mem = cfg.mem;

      # virtio-fs share for workspace
      shares = [
        {
          tag = "workspace";
          source = cfg.workspace.hostPath;
          mountPoint = "/workspace";
          proto = "virtiofs";
        }
      ];

      # VSOCK for host-guest communication (no TCP/IP)
      vsock = {
        cid = cfg.vsock.cid;
      };

      # No network interfaces - isolated sandbox
      interfaces = [ ];

      # Use virtiofs for /nix/store as well (read-only)
      writableStoreOverlay = null;
    };

    # Mount workspace via virtio-fs (hardened: no binaries, no suid)
    fileSystems."/workspace" = {
      device = "workspace";
      fsType = "virtiofs";
      options = [ "noexec" "nosuid" "nodev" ];
    };
  };
}
