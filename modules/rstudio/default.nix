{ config, pkgs, lib, ... }:

let
  cfg = config.PERSONAL.rstudio;
  rstudio-env = pkgs.rstudioWrapper.override {
    packages = with pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
      formatR   # used to style and format code chunks when rendered
    ];
  };
  texlive-env = (pkgs.texlive.combine {
    inherit (pkgs.texlive) scheme-full float;
  });
in rec {

}
