{ config
, pkgs
, pkgs-unstable
, lib ? config.lib
, libmint
, ...
}:
let
  cfg = config.CUSTOM.hardware.nvidia;

  inherit (builtins)
    hasAttr
    ;

  inherit (lib)
    mkIf
    mkEnableOption
    mkPackageOption
    mkOption
    mkBefore
    ;

  inherit (libmint)
    configureHost
    mkOutOfStoreSymlink
    ;

  nvidiaDriver = config.boot.kernelPackages.nvidia_x11;

  # NOTE: Config
  nvidia = {
    powerManagement = rec {
      default = {
        enable = true; # Enable dGPU systemd power management
        finegrained = false; # Enable PRIME offload power management
      };

      flowX13 = {
        enable = true;
        finegrained = false;
      };
      desktop = {
        enable = true;
        finegrained = false;
      };
    };

    # NOTE: Balancing between iGPU and dGPU
    prime = rec {
      default = {
        # NOTE: Sync and Offload mode cannot be used at the same time
        sync.enable = true; # Enable offloading to dGPU
        offload.enable = false; # convenience script to run on dGPU
      };

      desktop = default // {
        sync.enable = true; # Use dGPU for everything
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:16:0:0";
      };

      flowX13 = default // {
        sync.enable = true;
        reverseSync.enable = false;
        reverseSync.setupCommands.enable = false;

        offload.enable = false;
        offload.enableOffloadCmd = false;
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:8:0:0";
      };

      wsl = default // {
        sync.enable = false;
        #offload.enable = true;
        #offload.enableOffloadCmd = true;
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:16:0:0";
      };

      # TODO: fix the IDs
      flowX13-wsl = default // {
        sync.enable = false;
        offload.enable = true;
        offload.enableOffloadCmd = true;
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:8:0:0";
      };
    };

    # NOTE: Open kernel module: this is not the nouveau driver
    open = {
      default = true; # GTX 10XX gen is unsupported
    };

    # NOTE: Persists driver state across CUDA job runs, reduces setups/teardowns
    nvidiaPersistenced = {
      default = false;
      desktop = false;
      wsl = true;
      flowX13 = false;
      flowX13-wsl = true;
    };

    # NOTE: For laptops: enable better balancing between CPU and iGPU
    dynamicBoost = {
      default.enable = false;
      flowX13.enable = true;
      flowX13-wsl.enable = true;
    };

    videoAcceleration = {
      default = true;
      flowX13 = false;
    };

  };

  gpu-paths = {
    desktop = {
      card-igpu = "/dev/dri/by-path/pci-0000:16:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
    };
    wsl = {
      card-dgpu = "/dev/dri/by-path/platform-vgem-card";
    };
    flowX13 = {
      card-igpu = "/dev/dri/by-path/pci-0000:08:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
      render-igpu = "/dev/dri/by-path/pci-0000:08:00.0-render";
      render-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-render";
    };
    flowX13-wsl = {
      card-dgpu = "/dev/dri/by-path/platform-vgem-card";
    };
  };
in
{

  options.CUSTOM.hardware.nvidia = {

    enable = mkEnableOption "NVIDIA GPU settings for various hosts";

    proprietaryDrivers = {
      enable =
        mkEnableOption "proprietary NVIDIA drivers" // {
          default = true;
        };
      package =
        mkPackageOption config.boot.kernelPackages "nvidia_x11" {
          example = [ "nvidia_x11" "nvidia_x11_beta" "nvidia_x11_production" ];
        };
    };

    hostName = mkOption {
      default = config.networking.hostName;
      example = "desktop";
      description = "used to select host-specific configuration";
    };

  };

  config = lib.mkMerge [
    (mkIf cfg.enable {
      hardware.nvidia = {
        package = nvidiaDriver;
        modesetting.enable = true; # NOTE: Wayland requires this to be true
        nvidiaSettings = true;
      } // (configureHost cfg.hostName nvidia);

      services.xserver = {
        enable = true;
        # NOTE: If not set, will use nouveau drivers
        videoDrivers =
          if cfg.proprietaryDrivers.enable
          then [ "nvidia" "amdgpu" "modesetting" ]
          else [ "nouveau" "amdgpu" "modesetting" ];
      };

      environment.etc = (mkIf (hasAttr cfg.hostName gpu-paths) (
        mkBefore (lib.mapAttrs
          (key: val: { source = (mkOutOfStoreSymlink val); })
          gpu-paths."${cfg.hostName}"
        )
      ));

      environment.variables =
        {
          __GL_GSYNC_ALLOWED = "1";
          NVD_BACKEND = "direct";
        }
        // lib.optionalAttrs (cfg.hostName == "desktop") {
          LD_LIBRARY_PATH = "${nvidiaDriver}/lib:$LD_LIBRARY_PATH";
          EXTRA_LDFLAGS = "-L${nvidiaDriver}/lib $EXTRA_LDFLAGS";
          CUDA_PATH = "${pkgs.cudatoolkit}";
        };

      environment.systemPackages = [
        nvidiaDriver
        pkgs.cudatoolkit
        pkgs.cudaPackages.cudnn
        pkgs.cudaPackages.cuda_cudart
        pkgs.fmt.dev
      ];

      programs.nix-ld.libraries = [
        nvidiaDriver
      ];
    })
  ];

}
