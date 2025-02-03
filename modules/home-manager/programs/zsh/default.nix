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
    mkBefore
    mkAfter
    mkOption
    mkDefault
    mkEnableOption
    getExe
    removePrefix
    optionalAttrs
    ;


in
{
  options.CUSTOM.programs.zsh = {
    enable = mkEnableOption "My zsh configuration with antidote as plugin manager";
  };

  config = mkIf cfg.enable
    (
      let
        zDotDirAbs = config.xdg.configHome + "/zsh";
        zDotDirRel = removePrefix "${config.home.homeDirectory}/" zDotDirAbs;
        relToZDot = relPath: zDotDirAbs + "/${relPath}";

        compinit-cache-compile = ''
          if [ ! -n "''${__COMPINIT_WAS_RUN-}" ]; then 
            __COMPINIT_WAS_RUN=1
          
            # autoload:
            #   -U: do not expand aliases
            #   -z: autoload using zsh style (?)
            #
            # compinit:
            #   -u flag: use files in insecure directories without asking

            ZDOTDIR="''${ZDOTDIR:-$HOME}"
            ZSH_COMPDUMP="''${ZSH_COMPDUMP:-''${ZDOTDIR}/.zcompdump}"

            # Run faster compinit with -C, only check for new functions? don't re-check existing?
            #   Can be a source of bugs: if new completions added, will not be available
            #
            autoload -Uz compinit

            if [[ $ZSH_COMPDUMP(#qNmh-20) ]]; then
              compinit -C -d "$ZSH_COMPDUMP"
            else
              compinit -u -d "$ZSH_COMPDUMP"; touch "$ZSH_COMPDUMP"
            fi
            {
              autoload -Uz zcompile
              zcompare() {
                if [[ -s "''${1}" && ( ! -s "''${1}".zwc || "''${1}" -nt "''${1}".zwc) ]]; then
                  zcompile "''${1}"
                fi
              }

              # compile everything
              zcompare "''${ZDOTDIR}/.zcompdump}"
              zcompare "''${ZDOTDIR}/.zshrc}"
              zcompare "''${ZDOTDIR}/.zprofile}"
              zcompare "''${ZDOTDIR}/.zlogin}"
              zcompare "''${ZDOTDIR}/.zshenv}"
            } &!

          fi
        '';
      in
      {
        programs.zsh = {
          enable = true;
          dotDir = zDotDirRel;

          # Enable Nix completions and compinit
          enableCompletion = true;
          completionInit = compinit-cache-compile;
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
            readFile ./config/initExtraBeforeCompInit.zsh
            + ''
              # Get git completions: needs to be here for relative path to ./config/git-completion.bash
              zstyle ':completion:*:*:git:*' script ${./config}/git-completion.bash
              fpath=($ZDOTDIR ${./config} $fpath)

              # Must load complist before compinit
              zmodload zsh/complist
            ''
          ;

          shellAliases =
            {
              # Show colours by default
              grep = "grep --color=always";
              less = "less -R";

              # Pip Aliasing
              pip = "pip3";
            }
            // (optionalAttrs (!config.programs.eza.enable) {
              ls = "ls --color=always";
              ll = "ls -l --color=always";
            })
            // (optionalAttrs (config.programs.zoxide.enable) {
              cd = "z";
            })
            // (optionalAttrs (config.programs.bat.enable) {
              man = "batman";
            });

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
              "Aloxaf/fzf-tab"
              "zsh-users/zsh-completions"
              "zsh-users/zsh-autosuggestions"
              "zdharma-continuum/fast-syntax-highlighting"
            ];
          };

          initExtra = ''
            # +------------------+
            # | fzf-tab  Options |
            # +------------------+
            # disable sort when completing `git checkout`
            zstyle ':completion:*:git-checkout:*' sort false
            # set descriptions format to enable group support
            # NOTE: don't use escape sequences (like '%F{red}%d%f') here, fzf-tab will ignore them
            zstyle ':completion:*:descriptions' format '[%d]'
            # set list-colors to enable filename colorizing
            zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}
            # force zsh not to show completion menu, which allows fzf-tab to capture the unambiguous prefix
            zstyle ':completion:*' menu no
            # preview directory's content with eza when completing cd
            zstyle ':fzf-tab:complete:*' fzf-preview 'eza --icons=always -1 --color=always $realpath'

            # custom fzf flags
            # NOTE: fzf-tab does not follow FZF_DEFAULT_OPTS by default
            zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
            # To make fzf-tab follow FZF_DEFAULT_OPTS.
            # NOTE: This may lead to unexpected behavior since some flags break this plugin. See Aloxaf/fzf-tab#455.
            zstyle ':fzf-tab:*' use-fzf-default-opts yes
            # switch group using `<` and `>`
            zstyle ':fzf-tab:*' switch-group '<' '>'
          '';
        };

        xdg.configFile = {
          "${zDotDirAbs}" = {
            source = ./config;
            recursive = true;
          };
        };

        programs.alacritty.settings = mkIf config.programs.alacritty.enable {
          terminal.shell = "${config.programs.zsh.package}/bin/zsh";
        };
        programs.ghostty.settings.command = mkIf config.programs.ghostty.enable "${config.programs.zsh.package}/bin/zsh";
      }
    );
}
