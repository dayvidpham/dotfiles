# tmux keybindings - edit this file directly, then Prefix+r to reload

# Vi-style copy mode
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

# Split with current path (vim-style)
bind s split-window -v -c "#{pane_current_path}"
bind v split-window -h -c "#{pane_current_path}"

# Session picker on Tab
bind Tab choose-tree -Zs

# hjkl pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# HJKL pane swapping
bind H swap-pane -s '{left-of}'
bind J swap-pane -s '{down-of}'
bind K swap-pane -s '{up-of}'
bind L swap-pane -s '{right-of}'

# Resize panes with Ctrl+hjkl
bind -r C-h resize-pane -L 5
bind -r C-j resize-pane -D 5
bind -r C-k resize-pane -U 5
bind -r C-l resize-pane -R 5

# Quick window switching
bind -r n next-window
bind -r p previous-window

# Reload config
bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

# Sessionizer (fzf + zoxide)
bind f display-popup -E "tmux-sessionizer"

# True color support
set -ag terminal-overrides ",xterm-256color:RGB"
set -ag terminal-overrides ",ghostty:RGB"
