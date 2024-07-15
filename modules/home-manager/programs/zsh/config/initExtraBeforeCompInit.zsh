# ========== BEGIN ZSH CHANGES =========
# From this zsh completion guide
# https://thevaluable.dev/zsh-completion-guide-examples/
# https://github.com/Phantas0s/.dotfiles/blob/master/zsh/completion.zsh

# No longer beeps on ambiguous completion
unsetopt LIST_BEEP

# Enable colors (???)
autoload -U colors; colors

# +---------+
# | Options |
# +---------+

setopt GLOB_COMPLETE      # Show autocompletion menu with globs
unsetopt MENU_COMPLETE        # Automatically highlight first element of completion menu
setopt AUTO_LIST            # Automatically list choices on ambiguous completion.
setopt COMPLETE_IN_WORD     # Complete from both ends of a word.

# enable colored prompts
autoload -U promptinit && promptinit
# enable vcs_info to display git branch
autoload -Uz vcs_info
precmd() { vcs_info }

setopt PROMPT_SUBST

# Load more completions
# fpath=($DOTFILES/zsh/plugins/zsh-completions/src $fpath)

# Config location
# export ZDOTDIR="$HOME/.config/zsh"

KEYTIMEOUT=1                                               # 10ms delay before key sequence timeout
_comp_options+=(globdots)                                  # With hidden files


# Use hjlk in menu selection (during completion)
# Doesn't work well with interactive mode
bindkey -M menuselect '^h' vi-backward-char
bindkey -M menuselect '^k' vi-up-line-or-history
bindkey -M menuselect '^j' vi-down-line-or-history
bindkey -M menuselect '^l' vi-forward-char

bindkey -M menuselect '^g' clear-screen
bindkey -M menuselect '^i' vi-insert                      # Insert
bindkey -M menuselect '^[^M' accept-and-hold               # Hold
bindkey -M menuselect '^n' accept-and-infer-next-history  # Next
bindkey -M menuselect '\033' undo                          # Undo, ESC key
bindkey -M menuselect '^u' undo                          # Undo, ESC key

# +---------+
# | zstyles |
# +---------+

# Ztyle pattern
# :completion:<function>:<completer>:<command>:<argument>:<tag>

# Define completers
zstyle ':completion:*' completer _extensions _complete _approximate

# Use cache for commands using cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/.zcompcache"
# Complete the alias when _expand_alias is used as a function
zstyle ':completion:*' complete true

# Expand aliases
zle -C alias-expension complete-word _generic
bindkey '^Xa' alias-expension
zstyle ':completion:alias-expension:*' completer _expand_alias

# Allow you to select in a menu
zstyle ':completion:*' menu select
# Find command options first
# zstyle ':completion:*:complete:**' tag-order 'options'
# Generate matches in verbose form

# Autocomplete options for cd instead of directory stack
zstyle ':completion:*' complete-options true

zstyle ':completion:*' file-sort modification


zstyle ':completion:*:*:*:*:corrections' format '%F{yellow}!- %d (errors: %e) -!%f'
zstyle ':completion:*:*:*:*:descriptions' format '%F{green}-- %D %d --%f'
zstyle ':completion:*:*:*:*:messages' format ' %F{purple} -- %d --%f'
zstyle ':completion:*:*:*:*:warnings' format ' %F{red}-- no matches found --%f'
zstyle ':completion:*:default' list-prompt '%S%M matches%s'

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
# zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# enable detailed completions for files
# zstyle ':completion:*' file-list all

# Only display some tags for the command cd
zstyle ':completion:*:*:cd:*' tag-order local-directories directory-stack path-directories
# zstyle ':completion:*:complete:git:argument-1:' tag-order !aliases

# Required for completion to be in good groups (named after the tags)
zstyle ':completion:*' group-name ''

zstyle ':completion:*:*:-command-:*:*' group-order aliases builtins functions commands

# See ZSHCOMPWID "completion matching control"
# zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 

zstyle ':completion:*' keep-prefix true

zstyle -e ':completion:*:(ssh|scp|sftp|rsh|rsync):hosts' hosts 'reply=(${=${${(f)"$(cat {/etc/ssh_,~/.ssh/known_}hosts(|2)(N) /dev/null)"}%%[# ]*}//,/ })'

# Formatting for git branch in prompt
zstyle ':vcs_info:git:*' formats '%F{green}branch %b%f'

# Alternate prompt formatting: set prompt theme (see prompt for details)
#prompt fire black red black grey white white
#prompt redhat

# Custom prompt formatting
PROMPT='%F{cyan}[%f%F{red} %n %f@ %F{cyan}${PWD/#$HOME/~} ]%f [${vcs_info_msg_0_}] $ '

# +---------+
# | Plugins |
# +---------+


# # Load fzf
# [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# # Load fzf-tab plugin
# NOTE: fzf-tab needs to be loaded after compinit, but before plugins which will wrap widgets, such as zsh-autosuggestions or fast-syntax-highlighting!!
# source ${ZDOTDIR}/fzf-tab/fzf-tab.plugin.zsh

# ========== END ZSH CHANGES =========



# ========== BEGIN TERMINAL CHANGES =========

# ========== END TERMINAL CHANGES =========


