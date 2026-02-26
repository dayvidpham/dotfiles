# tmux keybindings - edit this file directly, then Prefix+r to reload

# ── Prefix mode toggle (Alt+Shift+Tab) ──────────────────────────────
# Tracks which prefix is active: "alt" (M-Space) or "ctrl" (C-Space)
# Root-table binding so it works regardless of current prefix
set -g @prefix-mode "alt"

bind -T root M-BTab if-shell -F '#{==:#{@prefix-mode},alt}' \
  'set -g prefix C-Space ; unbind M-Space ; bind C-Space send-prefix ; set -g @prefix-mode "ctrl" ; display "Prefix: Ctrl+Space"' \
  'set -g prefix M-Space ; unbind C-Space ; bind M-Space send-prefix ; set -g @prefix-mode "alt" ; display "Prefix: Alt+Space"'

# Status-left: colored prefix mode indicator
set -g status-left '#{?#{==:#{@prefix-mode},alt},#[bg=blue fg=black bold] ALT ,#[bg=green fg=black bold] CTRL }#[default] '

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

# Move current window to another session
bind M display-popup -E "tmux-move-window"

# Send pane: break into new window or join an existing one
bind S display-menu -T "Send pane" \
  "New window"           n "break-pane" \
  "Existing window..."   e "command-prompt -p 'Join window:' 'join-pane -s \"#{pane_id}\" -t \"%%\"'"

# Rename session
bind R command-prompt -I "#S" "rename-session '%%'"

# Name current pane
bind T command-prompt -p "Pane title:" "select-pane -T '%%'"

# ── Repo-based pane coloring ─────────────────────────────────────────
# Focus events (tmux-sensible already sets this; explicit for documentation)
set -g focus-events on

# Re-apply repo theme when switching panes (pass path directly to avoid tmux#3506)
set-hook -g pane-focus-in 'run-shell "tmux-repo-theme \"#{pane_current_path}\""'

# Pane border labels: title first, then session:window.pane
# Bold title text for worktree panes (when @repo-worktree is 1)
set -g pane-border-status top
set -g pane-border-format "#{?pane_title,#{?#{==:#{@repo-worktree},1}, #[bold]#{pane_title}#[nobold], #{pane_title}} - ,}#{session_name}:#{window_index}.#{pane_index} "

# True color support
set -ag terminal-overrides ",xterm-256color:RGB"
set -ag terminal-overrides ",ghostty:RGB"
