{
  config
  , pkgs
  , lib ? pkgs.lib
  , ... 
}:
let
  cfg = config.CUSTOM.hardware.nvidia;

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
      package = 
        mkPackageOption config.boot.kernelPackages.nvidiaPackages "stable" {};
    };
  };

  config = mkIf cfg.enable {
    hardware.opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        vaapiVdpau
      ];
    };

    hardware.nvidia = {
      package = cfg.package;
      modesetting.enable = true;    # NOTE: Sway will hang if not set
      nvidiaSettings = true;

      # NOTE: Ryzen 9 7950X3D has iGPU too
      #dynamicBoost.enable = true;   # Enable better balancing between CPU and iGPU
      powerManagement = {
        enable = false;              # Enable dGPU systemd power management
          finegrained = false;         # Enable PRIME offload power management
      };
      # Balancing between iGPU and dGPU
      prime = {
        sync.enable = true;         # Use dGPU for everything
      
      # NOTE: Sync and Offload mode cannot be used at the same time
      #offload.enable = true;            # Enable offloading to dGPU
      #offload.enableOffloadCmd = true;  # convenience script to run on dGPU
      
                nvidiaBusId = "PCI:1:0:0";
              amdgpuBusId = "PCI:16:0:0";
            };
      
      # NOTE: If screen tearing persists, might want to disable this
      # Open kernel module: this is not the nouveau driver
            open = false; # GTX 10XX gen is unsupported
      # we on the RTX 4090 now though!
          };
          services.xserver = {
            enable = true;
            videoDrivers = [ "nvidia" "amdgpu" ];    # NOTE: If commented, will use nouveau drivers
              xkb.variant = "";
            xkb.layout = "us";
          };
      
      # NOTE: To load nvidia drivers first
          boot.initrd.kernelModules = [ "nvidia" ];
          boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];
      # NOTE: Maybe fixes white screen flickering with AMD iGPU
    boot.kernelParams = [ "amdgpu.sg_display=0" ];

    programs.xwayland.enable = true;
}
