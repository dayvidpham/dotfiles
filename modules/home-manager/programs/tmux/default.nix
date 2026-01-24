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
    │                    Prefix: Ctrl+Space                         │
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
    │ Prefix f                │ Sessionizer (fzf + zoxide)          │
    │ Prefix r                │ Reload config                       │
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
    home.packages = [ sessionizer moveWindow ];
    programs.zsh.shellAliases.tmux-help = cheatsheet;
    programs.tmux = {
      enable = true;
      prefix = "C-Space";
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

    # Systemd user service to keep tmux server running at user login
    systemd.user.services.tmux = {
      Unit = {
        Description = "tmux server";
        Documentation = "man:tmux(1)";
      };

      Service = {
        Type = "forking";
        ExecStart = "${config.programs.tmux.package}/bin/tmux new-session -d -s main";
        ExecStop = "${config.programs.tmux.package}/bin/tmux kill-server";
        Restart = "on-failure";
        RestartSec = 10;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
