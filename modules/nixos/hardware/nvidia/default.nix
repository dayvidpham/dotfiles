{
  config
  , pkgs
  , lib ? pkgs.lib
  , libmint
  , ... 
}:
let
  cfg = config.CUSTOM.hardware.nvidia;

  nvidiaDriver = config.boot.kernelPackages.nvidia_x11_beta;
  #nvidiaDriver = pkgs.linuxPackages_latest.nvidia_x11_beta;

  # NOTE: Config
  nvidia = {
    powerManagement = rec {
      default = {
        enable      = true;         # Enable dGPU systemd power management
        finegrained = false;        # Enable PRIME offload power management
      };

      laptop = {
        finegrained = true;
      };
    };

    # NOTE: Balancing between iGPU and dGPU
    prime = rec {
      default = {
        # NOTE: Sync and Offload mode cannot be used at the same time
        sync.enable = false;      # Enable offloading to dGPU
        offload.enable = false;   # convenience script to run on dGPU
      };

      desktop = default // {
        sync.enable = true;         # Use dGPU for everything
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:16:0:0";
      };

      laptop = default // {
        offload.enable = true;
      };
    };

    # NOTE: Open kernel module: this is not the nouveau driver
    open = {
      default = false; # GTX 10XX gen is unsupported
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

  inherit (lib) 
    mkIf
    mkEnableOption
    mkPackageOption
    mkOption
    mkDefault
    mkBefore
    mkAfter
  ;

  inherit (libmint)
    configureHost
  ;

in {

  options.CUSTOM.hardware.nvidia = {

    enable = mkEnableOption "NVIDIA GPU settings for various hosts";

    proprietaryDrivers = {
      enable = 
        mkEnableOption "proprietary NVIDIA drivers" // { 
          default = true;
        };
      package = 
        mkPackageOption config.boot.kernelPackages "nvidia_x11_beta" {
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

    hardware.opengl = {
      enable          = true;
      driSupport      = true;
      driSupport32Bit = true;
      extraPackages   = mkIf cfg.proprietaryDrivers.enable (with pkgs; [
        nvidia-vaapi-driver
      ]);
    };

    hardware.nvidia = {
      package             = nvidiaDriver;
      modesetting.enable  = true;    # NOTE: Sway will hang if not set
      nvidiaSettings      = true;
    } // (configureHost cfg.hostName nvidia);

    programs.xwayland.enable = true;

    services.xserver = {
      enable = true;
      # NOTE: If not set, will use nouveau drivers
      videoDrivers = mkIf cfg.proprietaryDrivers.enable [ "nvidia" ];
    };

    boot = mkIf cfg.proprietaryDrivers.enable {
      # NOTE: To load nvidia drivers first 
      initrd.kernelModules = [ "nvidia" ];
      extraModulePackages = [ nvidiaDriver ];
    };

  };

}
