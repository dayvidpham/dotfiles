#!/usr/bin/env zsh


# +----------------+
# | Colour Options |
# +----------------+

zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# +---------+
# | Plugins |
# +---------+

# Plugin loading handled by antidote in zsh/default.nix home-manager module

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
# print "<user>@<host>" on right side of terminal
RPROMPT=$'%{\e[${colour[faint]}m%}%n@%m%{${reset_color}%}'
# cwd
PROMPT=$'\n''%F{cyan}%2~%f'
# print git branch if exists
PROMPT+=$'${PROMPT_VCS_BRANCH}\n'
# actual command prompt
PROMPT+='${VI_MODE} -> '

# +------------------+
# | Antidote Options |
# +------------------+
zstyle ':antidote:bundle:*' zcompile 'yes'
zstyle ':antidote:static' zcompile 'yes'
