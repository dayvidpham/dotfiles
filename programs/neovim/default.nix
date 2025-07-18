{ config
, pkgs
, pkgs-unstable
, lib ? pkgs.lib
, nil-lsp
, ...
}:
let
  treesitterWithGrammars = (pkgs-unstable.vimPlugins.nvim-treesitter.withPlugins (p: [
    p.awk
    p.bash
    p.bibtex
    p.c
    p.cpp
    p.comment
    p.cmake
    p.css
    p.scss
    p.diff
    p.dockerfile
    p.gitattributes
    p.gitcommit
    p.gitignore
    p.git_rebase
    p.haskell
    p.http
    p.hyprlang
    p.java
    p.javascript
    p.jq
    p.json5
    p.json
    p.jsonc
    p.lua
    p.luadoc
    p.make
    p.markdown
    p.markdown_inline
    p.meson
    p.nix
    p.printf
    p.python
    p.query
    p.r
    p.rasi
    p.regex
    p.rust
    p.toml
    p.typescript
    p.vim
    p.vimdoc
    p.yaml
    p.yuck
  ]));

  treesitter-parsers = pkgs-unstable.symlinkJoin {
    name = "treesitter-parsers";
    paths = treesitterWithGrammars.dependencies;
  };

  # NOTE: my own config
  # Pull in cargo and nil packages for Nix LSP
  system = pkgs-unstable.system;
  nil-lsp-pkg = nil-lsp.outputs.packages.${system}.nil;
  #  rust-minimal = nil-lsp.inputs.rust-overlay.packages.${system}.default.minimal;

  nvimConfig = "${config.xdg.configHome}/nvim";
in
{

  programs.neovim = {
    enable = true;
    vimAlias = true;
    coc.enable = false;
    withNodeJs = true;
    defaultEditor = true;
    package = pkgs-unstable.neovim-unwrapped;

    #plugins = with pkgs.vimPlugins; [
    #  {
    #    type = "lua";
    #    plugin = typescript-tools-nvim;
    #    config = "";
    #  }
    #];

    extraPackages = (with pkgs-unstable; [
      ripgrep
      fd
      lua-language-server
      black
      nixpkgs-fmt
      rust-analyzer-unwrapped
    ]
    ++ [
      # Python
      (python313.withPackages (pyPkgs: with pyPkgs; [
        rope
        ruff
        jedi
        python-lsp-server
        pylsp-rope
        python-lsp-ruff
      ]))
    ]
    ++ [
      # C++
      clang
      libclang
      clang-tools
    ]) ++ [
      pkgs.nixd
      nil-lsp-pkg
      #rust-minimal
      treesitterWithGrammars
    ];

    extraLuaConfig =
      ''
        vim.opt.runtimepath:append("${treesitter-parsers}")
        vim.g.clangd = "${pkgs-unstable.clang-tools}/bin/clangd"

        package.path = '${nvimConfig}/?.lua;' ..
          '${nvimConfig}/?/init.lua;' .. 
          '${nvimConfig}/minttea/lua/?/init.lua;' .. 
          '${nvimConfig}/minttea/lua/?.lua;' .. 
          package.path
        require('minttea')
      '';
  };

  xdg.configFile."nvim/minttea" = {
    source = ./nvim;
    recursive = true;
  };

  #home.file."${nvimConfigDir}/lua/nix/nvim-treesitter/init.lua".text = ''
  #  vim.opt.runtimepath:append("${treesitter-parsers}")
  #'';

  # Treesitter is configured as a locally developed module in lazy.nvim
  # we hardcode a symlink here so that we can refer to it in our lazy config
  xdg.dataFile."nvim/nix/nvim-treesitter/" = {
    recursive = true;
    source = treesitterWithGrammars;
  };

}
