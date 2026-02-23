{
  config,
  pkgs,
  lib ? config.lib,
  ...
}:
let
  cfg = config.CUSTOM.programs.tmux;

  inherit (lib)
    mkIf
    mkEnableOption
    getExe
    ;

  moveWindow = pkgs.writeShellScriptBin "tmux-move-window" ''
    current_session=$(tmux display-message -p '#S')

    # Format: "session-name (N windows)"
    target=$(tmux list-sessions -F '#S (#{session_windows} windows)' | \
      grep -v "^$current_session " | \
      ${getExe pkgs.fzf} --reverse --border --height=50% --prompt="Move window to: " | \
      sed 's/ (.*//')

    if [[ -n "$target" ]]; then
      tmux move-window -t "$target:"
    fi
  '';

  repoTheme = pkgs.writeShellScriptBin "tmux-repo-theme" ''
    # tmux-repo-theme: Set per-pane tmux styling based on git repo
    [[ -z "$TMUX" ]] && exit 0

    CONFIG="''${XDG_CONFIG_HOME:-$HOME/.config}/tmux/repo-colors.conf"

    # ── Create default config on first run ──
    if [[ ! -f "$CONFIG" ]]; then
      mkdir -p "$(dirname "$CONFIG")"
      cat > "$CONFIG" <<'CONF'
# tmux repo-colors: map git remotes to pane background colors
# Format: key=#rrggbb
# Key is the full git remote URL, or basename for local-only repos
#
# Examples:
# git@github.com:user/dotfiles.git=#1a1a2e
# git@github.com:user/my-project.git=#2e1a2e
# local-project=#1a2e1a
CONF
    fi

    # ── Parse config ──
    declare -A REPO_COLORS
    while IFS='=' read -r name color; do
      name="''${name## }"; name="''${name%% }"
      color="''${color## }"; color="''${color%% }"
      [[ -z "$name" || "$name" == \#* ]] && continue
      [[ "$color" =~ ^#[0-9a-fA-F]{6}$ ]] || continue
      REPO_COLORS["$name"]="$color"
    done < "$CONFIG"

    # ── Determine target directory ──
    target_dir="''${1:-$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)}"
    [[ -z "$target_dir" ]] && exit 0

    # ── Helper: lighten a hex color ──
    lighten_color() {
      local hex="''${1#\#}" amount="$2"
      local r=$((16#''${hex:0:2})) g=$((16#''${hex:2:2})) b=$((16#''${hex:4:2}))
      r=$(( r + amount > 255 ? 255 : r + amount ))
      g=$(( g + amount > 255 ? 255 : g + amount ))
      b=$(( b + amount > 255 ? 255 : b + amount ))
      printf "#%02x%02x%02x" "$r" "$g" "$b"
    }

    # ── Reset helper ──
    reset_pane() {
      tmux set -p window-style "default"
      tmux set -p @repo-worktree "0"
      tmux select-pane -T ""
    }

    # ── Detect git repo ──
    repo_root=$(${getExe pkgs.git} -C "$target_dir" rev-parse --show-toplevel 2>/dev/null) || {
      reset_pane; exit 0
    }

    # ── Resolve registry key: full remote URL, fallback to basename ──
    remote_url=$(${getExe pkgs.git} -C "$target_dir" remote get-url origin 2>/dev/null)
    repo_key="''${remote_url:-$(basename "$repo_root")}"
    color="''${REPO_COLORS[$repo_key]}"

    # Not in registry → reset
    [[ -z "$color" ]] && { reset_pane; exit 0; }

    # ── Get branch name ──
    branch=$(${getExe pkgs.git} -C "$target_dir" branch --show-current 2>/dev/null)
    branch="''${branch:-detached}"

    # ── Worktree detection ──
    if [[ -f "$repo_root/.git" ]]; then
      worktree_name=$(basename "$(${getExe pkgs.git} -C "$target_dir" rev-parse --git-dir)")
      tinted=$(lighten_color "$color" 20)
      tmux set -p window-style "bg=$tinted"
      tmux set -p @repo-worktree "1"
      tmux select-pane -T "🌿 $worktree_name ($branch)"
    else
      tmux set -p window-style "bg=$color"
      tmux set -p @repo-worktree "0"
      tmux select-pane -T "$branch"
    fi
  '';

  sessionizer = pkgs.writeShellScriptBin "tmux-sessionizer" ''
    if [[ $# -eq 1 ]]; then
      selected="$1"
    else
      # Show "new-session" option + zoxide directories
      selections=$(printf "[new]\n" && ${getExe pkgs.zoxide} query -l)
      selected=$(echo "$selections" | ${getExe pkgs.fzf} --reverse --border --height=50%)
    fi

    if [[ -z "$selected" ]]; then
      exit 0
    fi

    # If user selected "[new]", prompt for name and create without directory
    if [[ "$selected" == "[new]" ]]; then
      read -rp "Session name: " session_name
      if [[ -z "$session_name" ]]; then
        exit 0
      fi

      # Check if tmux is running
      tmux_running=$(pgrep tmux)

      if [[ -z "$TMUX" ]] && [[ -z "$tmux_running" ]]; then
        tmux new-session -s "$session_name"
        exit 0
      fi

      if ! tmux has-session -t="$session_name" 2>/dev/null; then
        tmux new-session -ds "$session_name"
      fi

      if [[ -z "$TMUX" ]]; then
        tmux attach-session -t "$session_name"
      else
        tmux switch-client -t "$session_name"
      fi
      exit 0
    fi

    # Create session name from directory (replace . with _)
    selected_name=$(basename "$selected" | tr . _)

    # Check if tmux is running
    tmux_running=$(pgrep tmux)

    # If not in tmux and tmux isn't running, start new session
    if [[ -z "$TMUX" ]] && [[ -z "$tmux_running" ]]; then
      tmux new-session -s "$selected_name" -c "$selected"
      exit 0
    fi

    # Create session if it doesn't exist
    if ! tmux has-session -t="$selected_name" 2>/dev/null; then
      tmux new-session -ds "$selected_name" -c "$selected"
    fi

    # Switch or attach to the session
    if [[ -z "$TMUX" ]]; then
      tmux attach-session -t "$selected_name"
    else
      tmux switch-client -t "$selected_name"
    fi
  '';

  cheatsheet = ''
    echo "
    ┌───────────────────────────────────────────────────────────────┐
    │                    tmux Cheatsheet                            │
    │                    Prefix: Alt+Space                          │
    └───────────────────────────────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Sessions                │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ tmux                    │ Start new session                   │
    │ tmux new -s <name>      │ Start named session                 │
    │ tmux ls                 │ List sessions                       │
    │ tmux a -t <name>        │ Attach to session                   │
    │ tmux kill-ses -t <name> │ Kill session                        │
    │ Prefix d                │ Detach from session                 │
    │ Prefix Tab              │ List/switch sessions                │
    │ Prefix \$               │ Rename session                      │
    └─────────────────────────┴─────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Windows                 │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ Prefix c                │ Create window                       │
    │ Prefix n / p            │ Next / previous window              │
    │ Prefix <number>         │ Go to window #                      │
    │ Prefix ,                │ Rename window                       │
    │ Prefix &                │ Kill window                         │
    │ Prefix w                │ List windows                        │
    └─────────────────────────┴─────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Panes                   │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ Prefix v                │ Split horizontally                  │
    │ Prefix s                │ Split vertically                    │
    │ Prefix h/j/k/l          │ Navigate panes (vim-style)          │
    │ Prefix H/J/K/L          │ Swap pane in direction              │
    │ Prefix C-h/j/k/l        │ Resize panes                        │
    │ Prefix z                │ Toggle pane zoom                    │
    │ Prefix x                │ Kill pane                           │
    │ Prefix q                │ Show pane numbers                   │
    └─────────────────────────┴─────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Copy Mode (vi)          │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ Prefix [                │ Enter copy mode                     │
    │ v                       │ Begin selection                     │
    │ y                       │ Yank selection                      │
    │ q / Escape              │ Exit copy mode                      │
    │ / or ?                  │ Search forward / backward           │
    │ n / N                   │ Next / previous match               │
    └─────────────────────────┴─────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Plugins                 │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ Prefix C-s              │ Save session (resurrect)            │
    │ Prefix C-r              │ Restore session (resurrect)         │
    │ Prefix P                │ Toggle logging (logging)            │
    │ Prefix M-p              │ Save pane history (logging)         │
    └─────────────────────────┴─────────────────────────────────────┘

    ┌─────────────────────────┬─────────────────────────────────────┐
    │ Custom                  │                                     │
    ├─────────────────────────┼─────────────────────────────────────┤
    │ Alt+Shift+Tab           │ Toggle prefix (Alt/Ctrl+Space)      │
    │ Prefix f                │ Sessionizer (fzf + zoxide)          │
    │ Prefix r                │ Reload config                       │
    │ Prefix S                │ Send pane to window # (prompt)      │
    │ Prefix R                │ Rename session (prompt)             │
    │ Prefix T                │ Name current pane (prompt)          │
    │ tmux-sessionizer        │ Run from shell                      │
    └─────────────────────────┴─────────────────────────────────────┘
    "
  '';
in
{
  options.CUSTOM.programs.tmux = {
    enable = mkEnableOption "tmux terminal multiplexer";
  };

  config = mkIf cfg.enable {
    home.packages = [ sessionizer moveWindow repoTheme ];
    programs.zsh.shellAliases.tmux-help = cheatsheet;
    programs.tmux = {
      enable = true;
      prefix = "M-Space";
      keyMode = "vi";
      mouse = true;
      baseIndex = 1;
      escapeTime = 0;
      historyLimit = 10000;
      terminal = "tmux-256color";
      sensibleOnTop = true;

      plugins = with pkgs.tmuxPlugins; [
        {
          plugin = resurrect;
          extraConfig = ''
            set -g @resurrect-strategy-nvim 'session'
            set -g @resurrect-capture-pane-contents 'on'
          '';
        }
        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '5'
          '';
        }
        {
          plugin = logging;
          extraConfig = ''
            set -g @logging-path '~/.local/share/tmux/logs'
          '';
        }
        yank
      ];

      # Source keybindings from symlinked file (edit without rebuild)
      extraConfig = ''
        source-file ~/.config/tmux/keybindings.tmux
      '';
    };

    # Symlink keybindings file out-of-store for live editing
    xdg.configFile."tmux/keybindings.tmux".source =
      config.lib.file.mkOutOfStoreSymlink "/home/minttea/dotfiles/modules/home-manager/programs/tmux/keybindings.tmux";

    # NOTE: Persistent tmux server is managed by NixOS-level systemd service
    # Enable via: CUSTOM.programs.tmux.server.enable = true; in NixOS config
    # This ensures tmux starts at boot and survives DE/WM/session closures
  };
}
