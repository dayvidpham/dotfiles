{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.rEnv;

  inherit (lib)
    mkEnableOption
    mkIf
    ;

  rstudio-env = pkgs.rstudioWrapper.override {
    packages = with pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
      reticulate
      formatR # used to style and format code chunks when rendered
    ];
  };

in
{
  options.CUSTOM.programs.rEnv = {
    enable = mkEnableOption "R dev env with RStudio and necessary TeX pkgs";
  };

  config = mkIf cfg.enable {
    home.packages = [
      rstudio-env
      pkgs.texliveFull
      pkgs.R
      pkgs.pandoc
    ];
  };
}
