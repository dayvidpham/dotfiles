{ 
  pkgs
  , conf
  , patches
  , cmd
  , dwl-source
  , ... 
}:
pkgs.dwl.overrideAttrs
  (finalAttrs: previousAttrs: {
    inherit patches;
    src = dwl-source;
    postPatch = 
      let 
        configFile = conf;
      in ''
        cp ${configFile} config.def.h
        substituteInPlace ./config.def.h --replace "@TERMINAL" "${cmd.terminal}"
      '';
  })
