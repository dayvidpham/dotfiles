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

  f-rstudio-env = (_pkgs: _pkgs.rstudioWrapper.override {
    rstudio = (_pkgs.rstudio.overrideAttrs {
      version = "2024.12.0+467";
    }).override {
      boost = _pkgs.boost186;
    };
    packages = with _pkgs.rPackages; [
      tidyverse
      knitr
      rmarkdown
      markdown
      reticulate
      formatR # used to style and format code chunks when rendered
      arrow
    ];
  });

  f-renv = (_pkgs: with _pkgs; [
    R
    (f-rstudio-env _pkgs)
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
    ] ++ (f-renv pkgs-unstable);

    xdg.configFile."rstudio/desktop.info".text = ''
      [General]
      desktop.renderingEngine=software
    '';
  };
}
