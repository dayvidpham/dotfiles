{ config
, pkgs
, pkgs-unstable
, pkgs-stable
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.rEnv;

  inherit (lib)
    mkEnableOption
    mkIf
    ;

  f-rstudio-env = (_pkgs: _pkgs.rstudioWrapper.override {
    packages = with _pkgs.rPackages; [
      tidyverse
      knitr
      bookdown
      rmarkdown
      markdown
      reticulate
      formatR # used to style and format code chunks when rendered
      arrow
    ];
  });

  f-rstudioWrapperBin = (_pkgs: _pkgs.writeShellApplication {
    name = "rstudio";
    runtimeInputs = [
      (f-rstudio-env _pkgs)
    ];
    text = ''
      RSTUDIO_CHROMIUM_ARGUMENTS="--disable-gpu" rstudio
    '';
  });

  f-renv = (_pkgs: with _pkgs; [
    R
    (f-rstudioWrapperBin _pkgs)
  ]);
in
{
  options.CUSTOM.programs.rEnv = {
    enable = mkEnableOption "R dev env with RStudio and necessary TeX pkgs";
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.texliveFull
      pkgs.pandoc
    ] ++ (f-renv pkgs-stable);

    #xdg.configFile."rstudio/desktop.info".text = ''
    #  [General]
    #  desktop.renderingEngine=software
    #'';
  };
}
