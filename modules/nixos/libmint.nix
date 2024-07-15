{ lib
, lib-hm
, runCommandLocal
, ...
}:
{
  # NOTE: Utils
  configureHost =
    let
      getHostConfig = (hostName: options:
        if (builtins.hasAttr hostName options)
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

  # NOTE: Copied from https://github.com/nix-community/home-manager/blob/90ae324e2c56af10f20549ab72014804a3064c7f/modules/files.nix#L64
  mkOutOfStoreSymlink = path:
    let
      pathStr = builtins.toString path;
      name = lib-hm.strings.storeFileName (baseNameOf pathStr);
    in
    runCommandLocal name { } ''ln -s ${lib.escapeShellArg pathStr} $out'';
}
