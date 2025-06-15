{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, ...
}:
let
  inherit (lib)
    mkDefault
    mkIf
    isAttrs# To check if a value is an attribute set
    isList# To check if a value is a list
    isFunction# To check if a value is a function
    ;

  # Condition function: Returns true only for non-nested types
  # We want to apply mkDefault ONLY IF the value is NOT an attrset, NOT a list, and NOT a function.
  shouldMakeDefault = value: !(isAttrs value || isList value || isFunction value);

  mkDefaults = (defset:
    lib.mapAttrsRecursiveCond shouldMakeDefault (_: value: mkDefault value) defset
  );
in
{
  environment.etc."openfortivpn/config" = {
    user = "root";
    group = "root";
    source = ./openfortivpn/config;
  };
}
