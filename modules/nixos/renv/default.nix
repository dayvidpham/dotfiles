{ config
, pkgs
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
    ];
  };

  texlive-env = (pkgs.texlive.combine {
    inherit (pkgs.texlive) scheme-full float;
  });

in
{
  options.CUSTOM.programs.rEnv = {
    enable = mkEnableOption "R dev env with RStudio and necessary TeX pkgs";
  };

  config = mkIf cfg.enable {
    home.packages = [
      rstudio-env
      texlive-env
      pkgs.pandoc
    ];
  };
}
