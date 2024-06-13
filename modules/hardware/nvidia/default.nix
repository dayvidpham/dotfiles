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
    powerManagement = let
      default = {
        enable      = true;         # Enable dGPU systemd power management
        finegrained = true;         # Enable PRIME offload power management
      };
    in {
      inherit default;

      desktop = default // {
        enable      = false;
        finegrained = false;
      };

      flowX13 = default;
    };

    # NOTE: Balancing between iGPU and dGPU
    prime = let 
      default = config.hardware.nvidia.prime;
    in {
      # NOTE: For laptops: enable better balancing between CPU and iGPU
      #dynamicBoost.enable = true;   

      # NOTE: Sync and Offload mode cannot be used at the same time
      #offload.enable = true;            # Enable offloading to dGPU
      #offload.enableOffloadCmd = true;  # convenience script to run on dGPU

      inherit default;

      desktop = default // {
        sync.enable = true;         # Use dGPU for everything
        nvidiaBusId = "PCI:1:0:0";
        amdgpuBusId = "PCI:16:0:0";
      };
    };

    # NOTE: Open kernel module: this is not the nouveau driver
    open = {
      default = false; # GTX 10XX gen is unsupported
                       # we on the RTX 4090 now though!
    };
    
    # NOTE: Persists driver state across CUDA job runs, reduces setups/teardowns
    nvidiaPersistenced = {
      default = true;
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
  options = {
    CUSTOM.hardware.nvidia = {
      enable = 
        mkEnableOption "NVIDIA GPU settings for various hosts";

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
  };

  config = mkIf cfg.enable {
    hardware.opengl = {
      enable          = true;
      driSupport      = true;
      driSupport32Bit = true;
      extraPackages   = with pkgs; [
        nvidia-vaapi-driver
      ];
    };

    hardware.nvidia = {
      package             = nvidiaDriver;
      modesetting.enable  = true;    # NOTE: Sway will hang if not set
      nvidiaSettings      = true;
    } // (configureHost cfg.hostName nvidia);

    programs.xwayland.enable = true;
    services.xserver = {
      enable = true;
      # TODO: Fix infinite recursion on this?
      #videoDrivers = # NOTE: If not set, will use nouveau drivers
      #  mkBefore [ "nvidia" ];
        #mkIf cfg.proprietaryDrivers.enable [ "nvidia" ];
    };

    boot = # NOTE: To load nvidia drivers first
      {
        initrd.kernelModules = [ "nvidia" ];
        extraModulePackages = [ nvidiaDriver ];
      };

    # NOTE: Maybe fixes white screen flickering with AMD iGPU
    # boot.kernelParams = [ "amdgpu.sg_display=0" ];
  };
}
