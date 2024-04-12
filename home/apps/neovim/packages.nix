{pkgs, ...}: {
  home.packages = with pkgs; [
    # c
    gcc # 插件需要
    # c/c++ tools with clang-tools, the unwrapped version won't
    # add alias like `cc` and `c++`, so that it won't conflict with gcc
    llvmPackages.clang-unwrapped
    gnumake
    # 查询文件内容使用
    ripgrep

    #-- python
    nodePackages.pyright
    (python311.withPackages (
      ps:
        with ps; [
          ruff-lsp
        ]
    ))

    #-- nix
    nil
    # rnix-lsp  # has been remove
    statix # Lints and suggestions for the nix programming language
    deadnix # Find and remove unused code in .nix source files

    #-- go
    go
    gopls # go language server
    delve # go debugger

    #-- lua
    stylua
    lua-language-server

    #-- rust
    rust-analyzer
    cargo # rust package manager
    rustfmt

    #-- misc
    marksman # lsp for markdown
    glow # markdown preview
    taplo # TOML language server / formatter / validator
    nodePackages.yaml-language-server
    # sqlfluff # SQL linter
    actionlint # GitHub Actions linter
    buf-language-server # bufls
    lazygit

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
  ];
}
