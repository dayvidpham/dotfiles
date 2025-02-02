# ========== BEGIN ZSH CHANGES =========
# From this zsh completion guide
# https://thevaluable.dev/zsh-completion-guide-examples/
# https://github.com/Phantas0s/.dotfiles/blob/master/zsh/completion.zsh

# No longer beeps on ambiguous completion
unsetopt LIST_BEEP

# Enable colors (???)
autoload -U colors; colors

# +--------------------+
# | Completion Options |
# +--------------------+

setopt GLOB_COMPLETE      # Show autocompletion menu with globs
unsetopt MENU_COMPLETE        # Automatically highlight first element of completion menu
setopt AUTO_LIST            # Automatically list choices on ambiguous completion.
setopt COMPLETE_IN_WORD     # Complete from both ends of a word.

_comp_options+=(globdots)                                  # With hidden files

# +---------+
# | zstyles |
# +---------+

# Ztyle pattern
# :completion:<function>:<completer>:<command>:<argument>:<tag>

zmodload zsh/complist
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

# Let users set LS_COLORS
# zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
# zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# List files in completion menu in style of `ls -l`
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

# +--------------+
# | Bindkey Init |
# +--------------+

# Activate vim mode
bindkey -v
KEYTIMEOUT=1                                               # 10ms delay before key sequence timeout

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

# +----------------+
# | Cursor Options |
# +----------------+

# Grabbed from this post: https://unix.stackexchange.com/q/433273
local _beam_cursor() {
    echo -ne '\e[5 q'
}
local _block_cursor() {
    echo -ne '\e[1 q'
}

local _cursor_select() {
    if [[ "$KEYMAP" == "main"
        || "$KEYMAP" == "viins"
        || "$KEYMAP" == "isearch"
        #|| "$1" == "beam"
    ]]; then
        _beam_cursor
    else
        _block_cursor
    fi
}

# Catppuccin Mocha
viinsert='%F{#a6e3a1}%B%S I %s%b%f'
vicommand='%F{#89b4fa}%B%S N %s%b%f'
vivisual='%F{#cba6f7}%B%S V %s%b%f'
vireplace='%F{#f9e2af}%B%S R %s%b%f'

export VI_MODE="$viinsert"

local _vi_mode() {
    # Source: https://www.reddit.com/r/zsh/comments/krwm0t/im_looking_for_a_way_to_display_vi_visual_and/
    #
    # INFO: Uncomment for debug info
    #zle -M "$KEYMAP : $ZLE_STATE = $VI_MODE"
    case "$KEYMAP$ZLE_STATE" in
        (vicmd*|command*)
            # Default
            export VI_MODE="$vicommand"
            _block_cursor
            ;;
        (visual*)
            # From $KEYMAP
            export VI_MODE="$vivisual"
            _block_cursor
            ;;
        (*overwrite*)
            # Set by $ZLE_STATE
            export VI_MODE="$vireplace"
            _block_cursor
            ;;
        (viins*|main*)
            # From $ZLE_STATE
            export VI_MODE="$viinsert"
            _beam_cursor
            ;;
    esac
    zle reset-prompt

}

local _line_init() {
    # start in viins
    zle -K viins
}

zle -N zle-keymap-select _vi_mode
zle -N zle-line-init _line_init

