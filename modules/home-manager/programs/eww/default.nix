{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.eww;
  dataHome = config.xdg.dataHome;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    removePrefix
    filterAttrs
    ;

  inherit (builtins)
    readDir
    attrNames
    substring
    stringLength
    ;

  removeHomePrefix = s: removePrefix config.home.homeDirectory s;

  getFontsInDir = (fontsDir: map
    (s: {
      name = s;
      value = {
        source = ./. + "/${s}";
        target = removeHomePrefix "${dataHome}/${substring 2 (stringLength s) s}";
      };
    })
    (map
      (subdir: (lib.path.removePrefix (dirOf fontsDir) fontsDir) + "/${subdir}")
      (attrNames
        (filterAttrs
          (key: val: val == "directory")
          (readDir fontsDir)
        ))
    )
  );

  fonts = builtins.listToAttrs (getFontsInDir ./fonts);

in
{
  options.CUSTOM.programs.eww = {
    enable = mkEnableOption "desktop widgets framework";
  };

  config = mkIf cfg.enable {
    programs.eww = {
      enable = true;
      configDir = ./config;
    };

    # Fonts
    home.file = fonts;
  };
}

