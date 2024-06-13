{
  lib
  , ...
}:

{
  # NOTE: Utils
  configureHost = 
    let
      getHostConfig = (hostName: options:
        if   (builtins.hasAttr hostName options)
        then options.${hostName}
        else options.default
      );
    in 
      (hostName: optionsSet:
        builtins.mapAttrs
          (optionKey: optionValueSet: 
            (lib.attrByPath [ hostName ] optionValueSet.default optionValueSet))
          optionsSet
      );
}
