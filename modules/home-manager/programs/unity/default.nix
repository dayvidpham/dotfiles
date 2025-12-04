{ config
, pkgs
, lib ? config.lib
, ...
}:
let
  cfg = config.CUSTOM.programs.unity;

  inherit (lib)
    mkIf
    mkOption
    mkDefault
    mkEnableOption
    ;

  pkg-nvim = config.programs.neovim.finalPackage;
  pkg-ghostty = config.programs.ghostty.package;
  pkg-unityhub = pkgs.unityhub.override {
    extraPkgs = pkgs: [
      # 1. The fake 'code' binary (for the VS Code trick)
      config.programs.vscode.package

      # 2. Your custom Unity-Neovim wrapper (optional, if you want to use it directly)
      (pkgs.writeShellScriptBin "unity-nvim" ''
        SOCKET_PATH="/tmp/nvim-unity.sock"
        
        # Logic to open file in existing neovim or start new one
        if ${pkg-nvim}/bin/nvim --server "$SOCKET_PATH" --remote-send "<C-\><C-n>" 2>/dev/null; then
          ${pkg-nvim}/bin/nvim --server "$SOCKET_PATH" --remote-tab-silent "$1"
          if [ ! -z "$2" ]; then
            ${pkg-nvim}/bin/nvim --server "$SOCKET_PATH" --remote-send ":$2<CR>"
          fi
        else
          # Change 'ghostty' to your terminal
          setsid ${pkg-ghostty}/bin/ghostty -e ${pkg-nvim}/bin/nvim --listen "$SOCKET_PATH" "$1" &
        fi
      '')

      # 3. Dependencies your scripts might need inside the bubble
      pkg-nvim
    ];
  };
in
{
  options.CUSTOM.programs.unity = {
    enable = mkEnableOption "opencode CLI AI assistant";
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkg-unityhub
    ];
  };
}
