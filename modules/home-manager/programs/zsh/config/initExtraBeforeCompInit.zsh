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
precmd() { 
    vcs_info 
    if [[ -n "${vcs_info_msg_0_}" ]]; then
        PROMPT_VCS_BRANCH=" [${vcs_info_msg_0_}]" # print git branch if exists
    else
        PROMPT_VCS_BRANCH="" # print git branch if exists
    fi
}

setopt PROMPT_SUBST

# Formatting for git branch in prompt
zstyle ':vcs_info:git:*' formats '%F{green}%b%f'

# Custom prompt formatting
RPROMPT=$'%{\e[${colour[faint]}m%}%n@%m%{${reset_color}%}'
PROMPT=$'\n''%F{cyan}%2~%f'  # cwd
PROMPT+='${PROMPT_VCS_BRANCH}'$'\n' # print git branch if exists
PROMPT+='  > '   # actual command prompt

# +------------------+
# | Antidote Options |
# +------------------+
zstyle ':antidote:bundle:*' zcompile 'yes'
zstyle ':antidote:static' zcompile 'yes'
