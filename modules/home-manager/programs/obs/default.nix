{ config
, pkgs
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.obs;

  inherit (lib)
    mkIf
    mkEnableOption
    ;
in
{
  options.CUSTOM.programs.obs = {
    enable = mkEnableOption "OBS Studio with background blur and a circular webcam mask";
  };

  config = mkIf cfg.enable {
    programs.obs-studio = {
      enable = true;
      # OBS reads cudaSupport only to add autoAddDriverRunpath; keep it scoped
      # here instead of globally (see flake.nix nixpkgs-options).
      package = pkgs.obs-studio.override { cudaSupport = true; };
      plugins = with pkgs.obs-studio-plugins; [
        obs-backgroundremoval
      ];
    };

    # For the webcam's Image Mask/Blend filter (Alpha Mask (Color Channel)).
    xdg.configFile."obs-studio/masks/circle-mask.png".source = ./circle-mask.png;
  };
}
