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
    ];
    lsp = [
      "jsonls"
      "yamlls"
      "taplo"
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
      # gotools 有 46 个命令、约 240 MiB，只用 goimports；它的二进制只引用 go 与 tzdata
      (pkgs.runCommand "goimports-${pkgs.gotools.version}"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
          preferLocalBuild = true;
          allowSubstitutes = false;
        }
        ''
          install -Dm755 ${pkgs.gotools}/bin/.goimports-wrapped $out/bin/goimports
          wrapProgram $out/bin/goimports --prefix PATH : ${pkgs.go}/bin
        ''
      )
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
