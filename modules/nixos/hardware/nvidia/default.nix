{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
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
    mkDefault
    mkBefore
    mkAfter
    mkMerge
    optionals
    ;

  inherit (libmint)
    configureHost
    mkOutOfStoreSymlink
    ;

  nvidiaDriver = config.boot.kernelPackages.nvidia_x11_beta;

  # NOTE: Config
  nvidia = {
    powerManagement = rec {
      default = {
        enable = true; # Enable dGPU systemd power management
        finegrained = false; # Enable PRIME offload power management
      };

      laptop = {
        finegrained = true;
      };
    };

    # NOTE: Balancing between iGPU and dGPU
    prime = rec {
      default = {
        # NOTE: Sync and Offload mode cannot be used at the same time
        sync.enable = false; # Enable offloading to dGPU
        offload.enable = false; # convenience script to run on dGPU
      };

      desktop = default // {
        sync.enable = true; # Use dGPU for everything
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:16:0:0";
      };

      laptop = default // {
        offload.enable = true;
        offload.enableOffloadCmd = true;
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:8:0:0";
      };
    };

    # NOTE: Open kernel module: this is not the nouveau driver
    open = {
      default = true; # GTX 10XX gen is unsupported
      # we on the RTX 4090 now though!
    };

    # NOTE: Persists driver state across CUDA job runs, reduces setups/teardowns
    nvidiaPersistenced = {
      default = false;
      desktop = true;
      flowX13 = true;
    };

    # NOTE: For laptops: enable better balancing between CPU and iGPU
    dynamicBoost = {
      default.enable = false;
      flowX13.enable = true;
    };

  };

  gpu-paths = {
    desktop = {
      card-igpu = "/dev/dri/by-path/pci-0000:16:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
    };
    flowX13 = {
      card-igpu = "/dev/dri/by-path/pci-0000:08:00.0-card";
      card-dgpu = "/dev/dri/by-path/pci-0000:01:00.0-card";
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

  config = mkIf cfg.enable {

    hardware.nvidia = {
      package = nvidiaDriver;
      modesetting.enable = true; # NOTE: Wayland requires this to be true
      nvidiaSettings = true;
    } // (configureHost cfg.hostName nvidia);

    programs.xwayland.enable = true;

    services.xserver = {
      enable = true;
      # NOTE: If not set, will use nouveau drivers
      videoDrivers =
        optionals cfg.proprietaryDrivers.enable [ "nvidia" ]
        ++ optionals (!cfg.proprietaryDrivers.enable) [ "nouveau" ]
      ;
    };

    environment.etc = mkIf (hasAttr cfg.hostName gpu-paths) {
      card-dgpu.source =
        mkOutOfStoreSymlink gpu-paths."${cfg.hostName}".card-dgpu;
      card-igpu.source =
        mkOutOfStoreSymlink gpu-paths."${cfg.hostName}".card-igpu;
    };

    # CUDA support?
    #boot.kernelModules = [ "nvidia-uvm" ];

    environment.variables =
      let
        hyprRenderer = mkMerge [
          (mkIf (config.programs.hyprland.enable && cfg.hostName == "desktop") {
            # Fuck it: use dGPU for everything
            WLR_DRM_DEVICES = "/etc/card-dgpu";
          })
          (mkIf (config.programs.hyprland.enable && cfg.hostName == "flowX13") {
            # TODO: Must test which value is correct for laptop
            # Use iGPU for everything
            WLR_DRM_DEVICES = "/etc/card-igpu";
          })
        ];
      in
      {
        # https://wiki.hyprland.org/Nvidia/#environment-variables
        LIBVA_DRIVER_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        __GL_GSYNC_ALLOWED = "1";

        # https://wiki.hyprland.org/Nvidia/#va-api-hardware-video-acceleration
        NVD_BACKEND = "direct";
      }
      // hyprRenderer;

  };
}
