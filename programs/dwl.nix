{ 
  config
  , pkgs
  , lib
  , dwl-source
  , ... 
}:
let
  cfg = config.programs.dwl;
  inherit (lib) mkEnableOption mkOption mkIf types;
  dwlPackage = pkgs.callPackage ../packages/dwl.nix { 
    inherit pkgs;
    inherit (cfg) patches cmd conf;
    inherit dwl-source;
  };
in
{
  options.programs.dwl = {
    enable = mkEnableOption "dwl";
    package = mkOption {
      type = types.package;
      default = dwlPackage;
    };
    conf = mkOption {
      type = types.path;
      default = ./config.def.h;
    };
    patches = mkOption {
      default = [ ];
    };
    cmd = {
      terminal = mkOption {
        default = "";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };

}
