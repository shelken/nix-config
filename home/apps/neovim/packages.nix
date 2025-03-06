{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  ...
}: let
  cfg = config.shelken.neovim;
in {
  home.packages = with pkgs;
    lib.optionals (!cfg.minimal)
    [
      # c
      # gcc # 插件需要
      # c/c++ tools with clang-tools, the unwrapped version won't
      # add alias like `cc` and `c++`, so that it won't conflict with gcc
      # llvmPackages.clang-unwrapped
      # clang-tools
      gnumake
      # 查询文件内容使用
      ripgrep

      #-- python
      pyright
      (python311.withPackages (
        ps:
          with ps; [
            pip
            ruff-lsp
            black # python formatter
          ]
      ))

      #-- nix
      nil
      # rnix-lsp  # has been remove
      statix # Lints and suggestions for the nix programming language
      deadnix # Find and remove unused code in .nix source files
      alejandra # Nix Code Formatter

      #-- go
      go
      gomodifytags
      iferr # generate error handling code for go
      impl # generate function implementation for go
      gotools # contains tools like: godoc, goimports, etc.
      gopls # go language server
      delve # go debugger

      #-- lua
      stylua
      lua-language-server

      #-- rust
      pkgs-unstable.rust-analyzer
      pkgs-unstable.cargo # rust package manager
      pkgs-unstable.rustfmt

      #-- misc
      marksman # lsp for markdown
      markdown-oxide # lsp for markdown
      glow # markdown preview
      taplo # TOML language server / formatter / validator
      nodePackages.yaml-language-server
      # sqlfluff # SQL linter
      actionlint # GitHub Actions linter
      buf # bufls
      tree-sitter # common language parser/highlighter
      nodePackages.prettier # common code formatter
      lazygit
      pngpaste # for img-clip plugins on mac

      #-- Cloud
      nodePackages.dockerfile-language-server-nodejs
      # terraform  # install via brew on macOS
      terraform-ls
      hadolint # Dockerfile linter
      helm-ls # helm lsp

      #-- frontend
      #javascript/typescript --#
      nodePackages.nodejs
      nodePackages.typescript
      nodePackages.typescript-language-server
      # html/css lsp
      nodePackages.vscode-langservers-extracted

      #-- bash
      nodePackages.bash-language-server
      shellcheck
      shfmt
    ]
    ++ lib.optionals (!stdenv.isDarwin) [
      gcc
      clang-tools
    ];
}
