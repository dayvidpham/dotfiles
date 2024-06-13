{
  config
  , pkgs
  , lib ? pkgs.lib
  , builtins
  , ... 
}:
let
  cfg = config.CUSTOM.hardware.nvidia;

  # NOTE: Utils
  configureHost = 
    let
      getHostConfig = hostName: options:
        if   (builtins.hasAttr hostName options)
        then options.${hostName}
        else options.default;
    in
      hostName: optionsSet:
        mapAttrs (optionKey: optionValueSet: getHostConfig hostName optionValueSet) 
        optionsSet;


  # NOTE: Config
  nvidia = {
    powerManagement = rec {
      default = {
        enable      = true;         # Enable dGPU systemd power management
        finegrained = true;         # Enable PRIME offload power management
      };

      desktop = default // {
        enable      = false;
        finegrained = false;
      };

      flowX13 = default;
    };

    # NOTE: Balancing between iGPU and dGPU
    prime = rec {
      # NOTE: For laptops: enable better balancing between CPU and iGPU
      #dynamicBoost.enable = true;   

      # NOTE: Sync and Offload mode cannot be used at the same time
      #offload.enable = true;            # Enable offloading to dGPU
      #offload.enableOffloadCmd = true;  # convenience script to run on dGPU

      default = config.nvidia.hardware.prime;

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
  ;
in {
  options = {
    CUSTOM.hardware.nvidia = {
      enable = 
        mkEnableOption "NVIDIA GPU settings for various hosts";

      proprietaryDrivers.enable = 
        mkEnableOption "proprietary NVIDIA drivers" // { 
          default = true;
        };

      hostName =
        mkDefaultOption config.networking.hostName {};

      package = 
        mkPackageOption config.boot.kernelPackages.nvidiaPackages "stable" {};
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
      package             = cfg.package;
      modesetting.enable  = true;    # NOTE: Sway will hang if not set
      nvidiaSettings      = true;
    } // configureHost cfg.hostName cfg.nvidia;

    programs.xwayland.enable = true;
    services.xserver = {
      enable = true;
      videoDrivers = # NOTE: If not set, will use nouveau drivers
        mkIf cfg.proprietaryDrivers.enable [ "nvidia" ];
    };

    boot = # NOTE: To load nvidia drivers first
      mkIf cfg.proprietaryDrivers.enable {
        initrd.kernelModules = [ "nvidia" ];
        extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
      };

    # NOTE: Maybe fixes white screen flickering with AMD iGPU
    # videoDrivers = [ "amdgpu" ];    # NOTE: If commented, will use nouveau drivers
    # boot.kernelParams = [ "amdgpu.sg_display=0" ];
  };
}
