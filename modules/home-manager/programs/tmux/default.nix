{
  config,
  pkgs,
  lib ? config.lib,
  osConfig ? { },
  ...
}:
let
  cfg = config.CUSTOM.programs.tmux;

  inherit (lib)
    mkIf
    mkEnableOption
    getExe
    ;

  # The login session's runtime dir (/run/user/<uid>). Home Manager's tmux
  # module (secureSocket) otherwise sets TMUX_TMPDIR=$XDG_RUNTIME_DIR, which in
  # a nested session (wayvnc/remote-session uses XDG_RUNTIME_DIR=/run/user/<uid>/remote)
  # points somewhere with no tmux server, so `tmux a` fails there.
  loginRuntimeDir =
    let
      uid = osConfig.users.users.${config.home.username}.uid or null;
    in
    if uid != null then "/run/user/${toString uid}" else "/run/user/1000";

  # Hook: capture Claude Code session IDs for tmux-resurrect restore.
  # Maps each Claude pane to its session UUID via ~/.claude/sessions/<PID>.json,
  # and captures whether --dangerously-skip-permissions was active.
  #
  # One `tmux list-panes` call builds a pane_pid -> pane map; each session then
  # walks its /proc parent chain with no further tmux clients (the old version
  # called `tmux list-panes` once per process-tree level). The file is published
  # atomically, and a previous good file is kept if the server doesn't answer.
  claudeSave = pkgs.writeShellScript "tmux-claude-save" ''
    CLAUDE_FILE="$HOME/.tmux/resurrect/claude_panes.txt"
    TMP_FILE="$CLAUDE_FILE.tmp"

    # One tmux call: pane pid -> session:window.pane
    declare -A PANE_OF
    panes_ok=0
    while read -r pane_pid target; do
      [ -n "$pane_pid" ] || continue
      PANE_OF[$pane_pid]="$target"
      panes_ok=1
    done < <(${pkgs.coreutils}/bin/timeout 5 ${getExe pkgs.tmux} list-panes -a -F '#{pane_pid} #{session_name}:#{window_index}.#{pane_index}' 2>/dev/null)

    # Server didn't answer - keep the previous good file instead of clobbering it
    [ "$panes_ok" -eq 1 ] || exit 0

    : > "$TMP_FILE"

    for sf in "$HOME"/.claude/sessions/*.json; do
      [ -e "$sf" ] || continue
      pid=''${sf##*/}
      pid=''${pid%.json}
      case "$pid" in ""|*[!0-9]*) continue ;; esac
      [ -r "/proc/$pid/cmdline" ] || continue

      # One cmdline read gives us both: is this really claude, and was bypass on?
      bypass=""
      is_claude=0
      while IFS= read -r -d "" arg; do
        [ "$arg" = "--dangerously-skip-permissions" ] && bypass="--dangerously-skip-permissions"
        case "$arg" in claude|*/claude) is_claude=1 ;; esac
      done < "/proc/$pid/cmdline"
      [ "$is_claude" -eq 1 ] || continue # stale file / pid reuse guard

      session_id=$(${getExe pkgs.gnugrep} -o '"sessionId":"[^"]*"' "$sf" | ${pkgs.coreutils}/bin/cut -d'"' -f4)
      [ -z "$session_id" ] && continue

      # Walk parents in pure bash: /proc/<pid>/status PPid line, no forks
      p=$pid
      target=""
      while [ "$p" -gt 1 ]; do
        target="''${PANE_OF[$p]}"
        [ -n "$target" ] && break
        ppid=""
        while read -r key val _; do
          [ "$key" = "PPid:" ] && { ppid="$val"; break; }
        done < "/proc/$p/status"
        [ -n "$ppid" ] || break
        p=$ppid
      done
      [ -n "$target" ] || continue

      printf '%s\t%s\t%s\n' "$target" "$session_id" "$bypass" >> "$TMP_FILE"
    done

    # Atomic publish
    ${pkgs.coreutils}/bin/mv -f "$TMP_FILE" "$CLAUDE_FILE"
  '';

  # Hook: restore Claude Code sessions with exact session IDs
  claudeRestore = pkgs.writeShellScript "tmux-claude-restore" ''
    CLAUDE_FILE="$HOME/.tmux/resurrect/claude_panes.txt"
    [ -f "$CLAUDE_FILE" ] || exit 0

    while IFS="$(printf '\t')" read -r target session_id bypass; do
      [ -z "$target" ] || [ -z "$session_id" ] && continue

      session_name="''${target%%:*}"
      tmux has-session -t "$session_name" 2>/dev/null || continue

      cmd="claude"
      [ -n "$bypass" ] && cmd="$cmd $bypass"
      cmd="$cmd --resume $session_id"

      tmux send-keys -t "$target" "$cmd" Enter
    done < "$CLAUDE_FILE"
  '';

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

  # Picker: render the current window at a chosen attached client's size.
  # Bound in keybindings.tmux (Prefix Z); the popup passes the target window.
  # Picking a client pins the window via `resize-window` (sets window-size=manual
  # on it); "auto" removes the override so the global window-size applies again.
  clientSize = pkgs.writeShellScriptBin "tmux-client-size" ''
    target_window="''${1:-}"
    [ -n "$target_window" ] || target_window=$(${getExe pkgs.tmux} display-message -p '#{window_id}')

    selection=$(
      {
        printf 'auto|-|global window-size (tmux decides)\n'
        ${getExe pkgs.tmux} list-clients -F '#{client_tty}|#{client_width}x#{client_height}|#{client_session}|#{client_termname}'
      } | ${getExe pkgs.fzf} --reverse --border --height=100% --prompt='Render window at> '
    ) || exit 0
    [ -n "$selection" ] || exit 0

    IFS='|' read -r tty size session info <<< "$selection"

    if [ "$tty" = "auto" ]; then
      # Drop the per-window override; tmux refits via the global window-size
      ${getExe pkgs.tmux} setw -t "$target_window" -u window-size
      ${getExe pkgs.tmux} display-message "Window sizing: auto"
      exit 0
    fi

    case "$size" in
      [0-9]*x[0-9]*) ;;
      *) exit 0 ;;
    esac
    w=''${size%x*}
    h=''${size#*x}

    # Status lines for this session (tmux's `status` option is the line count);
    # the window area is client height minus status lines, as tmux computes it.
    # -A includes inherited values: the session often only inherits `status`.
    status_lines=$(${getExe pkgs.tmux} show-options -A -t "$session" -v status)
    [ -n "$status_lines" ] || status_lines=$(${getExe pkgs.tmux} show-options -gv status)
    if [ "$status_lines" = "off" ]; then
      status_lines=0
    elif [ -z "$status_lines" ] || [ "$status_lines" = "on" ]; then
      status_lines=1
    fi

    ${getExe pkgs.tmux} resize-window -t "$target_window" -x "$w" -y "$((h - status_lines))"
    ${getExe pkgs.tmux} display-message "Window sizing: pinned ''${w}x$((h - status_lines)) ($session, $info)"
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
      tinted=$(lighten_color "$color" 45)
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
    │ Prefix Z                │ Render at client size (picker)      │
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
    home.packages = [ sessionizer moveWindow repoTheme clientSize pkgs.sesh ]; # sesh: Prefix f picker in keybindings.tmux
    programs.zsh.shellAliases.tmux-help = cheatsheet;

    # Override HM's tmux-module default ($XDG_RUNTIME_DIR) so every session's
    # shells point at the login session's tmux server, including nested
    # remote-session/VNC shells whose XDG_RUNTIME_DIR is /run/user/<uid>/remote.
    home.sessionVariables.TMUX_TMPDIR = lib.mkForce loginRuntimeDir;
    programs.tmux = {
      enable = true;
      prefix = "M-Space";
      keyMode = "vi";
      mouse = true;
      focusEvents = true; # required by the pane-focus-in hook (tmux-repo-theme); hm default is off
      baseIndex = 1;
      escapeTime = 0;
      historyLimit = 10000;
      terminal = "tmux-256color";
      sensibleOnTop = true;

      plugins = with pkgs.tmuxPlugins; [
        {
          plugin = resurrect.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              # Fix: bash 'read' with IFS=$'\t' collapses consecutive tabs,
              # so an empty #{pane_title} shifts all columns in the save file.
              # Restore then parses the dir as "0"/"1" -> empty -> $HOME.
              # Fix: fall back to last two CWD segments when pane_title is empty.
              substituteInPlace scripts/save.sh \
                --replace-fail 'format+="#{pane_title}"' \
                'format+="#{?pane_title,#{pane_title},#{s|^.*/([^/]+/[^/]+)$|\1|:pane_current_path}}"'
            '';
          });
          extraConfig = ''
            set -g @resurrect-strategy-nvim 'session'
            set -g @resurrect-capture-pane-contents 'on'
            # Capture only the visible screen per pane, not the full 10k-line
            # history: full-history captures across ~50 panes swamped the
            # server during saves under IO pressure (2026-09-18 hang).
            set -g @resurrect-pane-contents-area 'visible'
            set -g @resurrect-hook-post-save-all '${claudeSave}'
            set -g @resurrect-hook-post-restore-all '${claudeRestore}'
          '';
        }
        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            # 15 min (was 5): under IO pressure a save could take longer than
            # 5 min, so saves overlapped and piled capture-pane load on the
            # server until it stopped responding (2026-09-18).
            set -g @continuum-save-interval '15'
          '';
        }
        {
          plugin = logging;
          extraConfig = ''
            set -g @logging-path '${config.home.homeDirectory}/.local/share/tmux/logs'
          '';
        }
        yank
      ];

      # Source keybindings from symlinked file (edit without rebuild)
      extraConfig = ''
        # Fit windows to the smallest attached client so nothing is ever clipped;
        # Prefix Z (keybindings.tmux) can pin a window to a specific client's size.
        setw -g window-size smallest

        # tmux-sensible sets this to 5s; 15s cuts the status-right
        # #(continuum_save.sh) fork churn by 3x. Must load after the plugins.
        set -g status-interval 15

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
