{
  config
  , pkgs
  , libs
  , ... 
}:
let
  cfg = config.CUSTOM.renv;
  rstudio-env = pkgs.rstudioWrapper.override { 
    packages = with pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
    ];
  };
  # Need scheme-full for proper integration with RMarkdown
  texlive-env = (pkgs.texlive.combine {
    inherit (pkgs.texlive) scheme-full float;
  });
in rec {
  
}
