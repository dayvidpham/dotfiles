{ config
, pkgs
, lib ? pkgs.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.zsh;

  inherit (builtins)
    readFile
    ;

  inherit (lib)
    mkIf
    mkMerge
    mkAfter
    mkOption
    mkDefault
    mkEnableOption
    getExe
    removePrefix
    ;


in
{
  options.CUSTOM.programs.zsh = {
    enable = mkEnableOption "My zsh configuration with antidote as plugin manager";
  };

  config = mkIf cfg.enable (
    let
      zDotDirAbs = config.xdg.configHome + "/zsh";
      zDotDirRel = removePrefix "${config.home.homeDirectory}/" zDotDirAbs;
      relToZDot = relPath: zDotDirAbs + "/${relPath}";
    in
    {
      programs.zsh = {
        enable = true;
        dotDir = zDotDirRel;

        enableCompletion = true; # Nix completions

        # Both plugins below provided via antidote
        autosuggestion.enable = false;
        syntaxHighlighting.enable = false;

        history = {
          size = 10000;
          save = 10000;
          share = true;
          extended = true;
        };

        initExtraBeforeCompInit =
          ''
            # Must load complist before compinit
            zmodload zsh/complist
          ''
          + readFile ./config/initExtraBeforeCompInit.zsh
          + ''
            zstyle ':completion:*:*:git:*' script ${./config}/git-completion.bash
            fpath=($ZDOTDIR ${./config} $fpath)
          ''
        ;

        completionInit = "autoload -U compinit && compinit -u";

        shellAliases = {
          # Show colours by default
          ls = "ls --color=always";
          ll = "ls -l --color=always";
          grep = "grep --color=always";
          less = "less -R";

          # Pip Aliasing
          pip = "pip3";
        };

        sessionVariables = {
          # Disable insecure directory checks
          ZSH_DISABLE_COMPFIX = "true";
          # Override default plugin behaviour
          ZSH_AUTOSUGGEST_STRATEGY = [ "history" "completion" ];
        };

        localVariables = {
          HISTTIMEFORMAT = "%d/%m/%y %T ";

          CLICOLOR = 1;
          LS_COLORS = (readFile ./config/ls-colors.env);
          LSCOLORS = "ehfxcxdxbxegedabagacad";
        };

        antidote = {
          enable = true;
          plugins = [
            "zsh-users/zsh-completions"
            "zsh-users/zsh-autosuggestions"
            "zdharma-continuum/fast-syntax-highlighting"
          ];
        };
      };

      xdg.configFile = {
        "${zDotDirAbs}" = {
          source = ./config;
          recursive = true;
        };
      };

      programs.alacritty.settings = mkIf config.programs.alacritty.enable {
        shell = "${getExe pkgs.zsh}";
      };
    }
  );
}
