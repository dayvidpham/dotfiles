{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.git;
  inherit (lib)
    mkIf
    ;
in
{
  options.CUSTOM.programs.git =
    let
      inherit (lib)
        mkEnableOption
        ;
    in
    {
      enable = mkEnableOption ''
        enable Git with some custom configs
          - save credentials on disk
          - use libsecret as a credential helper to encrypt saved credentials
      '';
    };

  config =
    mkIf cfg.enable {
      programs.git = {
        enable = true;
        package = pkgs.gitFull;
        config = {
          init.defaultBranch = "main";
          user.name = "dayvidpham";
          user.email = "dayvidpham@gmail.com";
          credential.helper = "${pkgs.gitFull}/bin/git-credential-libsecret";
          push.autoSetupRemote = "true";
          worktree.guessRemote = "true";
        };
      };
    };
}
