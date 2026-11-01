# 语言表：每种语言的外部工具、LSP、formatter、linter、treesitter 语法都写在这里
# default.nix 把它拆成 home.packages、treesitter 插件和 vim.g.nix_languages（供 config/ 读取）
#   packages   装进 PATH 的工具
#   lsp        nvim-lspconfig 的配置名（vim.lsp.enable）
#   formatters filetype -> conform formatter 名
#   linters    filetype -> nvim-lint linter 名
#   grammars   nvim-treesitter grammar 名
pkgs: {
  nix = {
    packages = [
      pkgs.nil
      pkgs.nixfmt
    ];
    lsp = [ "nil_ls" ];
    formatters.nix = [ "nixfmt" ];
    grammars = [ "nix" ];
  };

  lua = {
    packages = [
      pkgs.lua-language-server
      pkgs.stylua
    ];
    lsp = [ "lua_ls" ];
    formatters.lua = [ "stylua" ];
    grammars = [
      "lua"
      "luadoc"
      "vim"
      "vimdoc"
      "query"
    ];
  };

  bash = {
    # bash-language-server 自动调用 PATH 中的 shellcheck
    packages = [
      pkgs.bash-language-server
      pkgs.shellcheck
      pkgs.shfmt
    ];
    lsp = [ "bashls" ];
    formatters.sh = [ "shfmt" ];
    grammars = [ "bash" ];
  };

  data = {
    packages = [
      pkgs.vscode-langservers-extracted
      pkgs.yaml-language-server
      pkgs.taplo
      pkgs.marksman
    ];
    lsp = [
      "jsonls"
      "yamlls"
      "taplo"
      "marksman"
    ];
    formatters.toml = [ "taplo" ];
    grammars = [
      "json"
      "yaml"
      "toml"
      "markdown"
      "markdown_inline"
    ];
  };

  go = {
    packages = [
      pkgs.gopls
      pkgs.gotools
    ];
    lsp = [ "gopls" ];
    formatters.go = [ "goimports" ];
    grammars = [
      "go"
      "gomod"
      "gosum"
      "gowork"
    ];
  };

  # rust-analyzer / rustfmt 由 features/cli/tui.nix 的 Rust 工具链提供
  rust = {
    lsp = [ "rust_analyzer" ];
    formatters.rust = [ "rustfmt" ];
    grammars = [ "rust" ];
  };

  python = {
    packages = [
      pkgs.pyright
      pkgs.ruff
    ];
    lsp = [
      "pyright"
      "ruff"
    ];
    formatters.python = [
      "ruff_organize_imports"
      "ruff_format"
    ];
    grammars = [ "python" ];
  };

  web = {
    # html / cssls 来自 data 里的 vscode-langservers-extracted
    packages = [
      pkgs.typescript-language-server
      pkgs.typescript
      pkgs.prettier
    ];
    lsp = [
      "ts_ls"
      "html"
      "cssls"
    ];
    formatters = {
      javascript = [ "prettier" ];
      javascriptreact = [ "prettier" ];
      typescript = [ "prettier" ];
      typescriptreact = [ "prettier" ];
      html = [ "prettier" ];
      css = [ "prettier" ];
      json = [ "prettier" ];
    };
    grammars = [
      "javascript"
      "typescript"
      "tsx"
      "html"
      "css"
    ];
  };

  container = {
    packages = [
      pkgs.dockerfile-language-server
      pkgs.hadolint
      pkgs.helm-ls
    ];
    lsp = [
      "dockerls"
      "helm_ls"
    ];
    linters.dockerfile = [ "hadolint" ];
    grammars = [
      "dockerfile"
      "helm"
    ];
  };

  tooling = {
    packages = [
      pkgs.just-lsp
      pkgs.buf
      pkgs.actionlint
    ];
    lsp = [
      "just"
      "buf_ls"
    ];
    formatters.proto = [ "buf" ];
    # config/ 只对 .github/workflows 下的文件跑 actionlint
    linters.yaml = [ "actionlint" ];
    grammars = [
      "just"
      "proto"
    ];
  };

  git = {
    grammars = [
      "diff"
      "gitcommit"
      "git_rebase"
      "regex"
    ];
  };
}
