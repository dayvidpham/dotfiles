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
    mkOption
    mkDefault
    mkEnableOption
    ;

in
{
  options.CUSTOM.programs.zsh = {
    enable = mkEnableOption "System-wide configuration needed for zsh";
  };

  config = mkIf cfg.enable {
    users.defaultUserShell = pkgs.zsh;
    programs.zsh = {
      enable = true;

      shellAliases = {
        # Show colours by default
        ls = "ls --color=always";
        ll = "ls -l --color=always";
        grep = "grep --color=always";
        less = "less -R";
      };

      # Load order:
      # For each item, first /etc/z<file>, then ${ZDOTDOR}/.z<file>
      #   zshenv (all shells)
      #   zprofile (login shells)
      #   zshrc (interactive shells)
      #   zlogin (login shells)
      #   zlogout (when login shell exits)

      loginShellInit = readFile ./etc/zprofile.zsh;
      interactiveShellInit = readFile ./etc/zshrc.zsh;

      enableCompletion = true;
      # defer running compinit: user decides when since user's plugins may require it
      enableGlobalCompInit = false;

      promptInit = ''
        # +----------------+
        # | Prompt Options |
        # +----------------+

        # enable colored prompts
        autoload -U promptinit && promptinit
        # enable vcs_info to display git branch
        autoload -Uz vcs_info
        precmd() { vcs_info }

        setopt PROMPT_SUBST

        # Formatting for git branch in prompt
        zstyle ':vcs_info:git:*' formats '%F{green}%b%f'

        # Alternate prompt formatting: set prompt theme (see prompt for details)
        #prompt fire black red black grey white white
        #prompt redhat

        # Default: should be overridden by each user's personal prompt config
        PROMPT='%F{orange}[%f%F{red} %n %f@ %F{orange}''${PWD/#$HOME/~} ]%f [''${vcs_info_msg_0_}] $ '
      '';
    };

    environment.etc = {
      zlogin = {
        source = ./etc/zlogin.zsh;
      };
    };
  };
}




