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

  nvidiaDriver = config.boot.kernelPackages.nvidia_x11;

  # NOTE: Config
  nvidia = {
    powerManagement = rec {
      default = {
        enable = true; # Enable dGPU systemd power management
        finegrained = false; # Enable PRIME offload power management
      };

      laptop = {
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

      laptop = default // {
        sync.enable = true;
        #offload.enable = true;
        #offload.enableOffloadCmd = true;
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
      desktop = true;
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

  config = mkIf cfg.enable
    {

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
          then [ "nvidia" ]
          else [ "nouveau" ];
      };

      environment.etc = mkIf (hasAttr cfg.hostName gpu-paths)
        (
          lib.mapAttrs
            (key: val: { source = (mkOutOfStoreSymlink val); })
            gpu-paths."${cfg.hostName}"
        );
      #{
      #  card-dgpu.source = mkIf (gpu-paths."${cfg.hostName}" ? card-dgpu) (mkOutOfStoreSymlink gpu-paths."${cfg.hostName}".card-dgpu);
      #  card-igpu.source = mkIf (gpu-paths."${cfg.hostName}" ? card-igpu) (mkOutOfStoreSymlink gpu-paths."${cfg.hostName}".card-igpu);
      #};

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
