#!/usr/bin/env zsh


# +----------------+
# | Colour Options |
# +----------------+

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# +---------+
# | Plugins |
# +---------+


# # Load fzf
# [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# # Load fzf-tab plugin
# NOTE: fzf-tab needs to be loaded after compinit, but before plugins which will wrap widgets, such as zsh-autosuggestions or fast-syntax-highlighting!!
# source ${ZDOTDIR}/fzf-tab/fzf-tab.plugin.zsh

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

# Custom prompt formatting
PROMPT='%F{cyan}[%f%F{red} %n %f@ %F{cyan}${PWD/#$HOME/~} ]%f [${vcs_info_msg_0_}] $ '

# +------------------+
# | Antidote Options |
# +------------------+
zstyle ':antidote:bundle:*' zcompile 'yes'
zstyle ':antidote:static' zcompile 'yes'
