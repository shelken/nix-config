# Neovim
#   neovim-minimal（core）：nvim、config/、常用语法高亮、内置 autocomplete；不装语言工具，服务器也能用
#   neovim（tui 及以上）：再加语言工具、LSP 与插件；shelken.neovim.minimal = true 时不加
# 语言工具链见 _languages.nix，Lua 配置见 config/
{ config, ... }:
let
  hmModules = config.flake.modules.homeManager;
  # 没有语言工具时也想要的 treesitter 高亮；full 只追加表里其余语法
  baseGrammars = [
    "nix"
    "bash"
    "json"
    "yaml"
    "toml"
    "dockerfile"
    "diff"
    "gitcommit"
    "git_rebase"
  ];
  # 同 nvim-treesitter.withPlugins：parser 与高亮 queries 是两个插件，缺 queries 就没有高亮
  # 不用 withPlugins 是因为两层各自追加语法，它会产生两个同名 nvim-treesitter
  grammarPlugins =
    pkgs:
    let
      ts = pkgs.vimPlugins.nvim-treesitter;
    in
    pkgs.lib.concatMap (
      name: [ ts.grammarPlugins.${name} ] ++ pkgs.lib.optional (ts.queries ? ${name}) ts.queries.${name}
    );
in
{
  flake.modules.homeManager.core.imports = [ hmModules.neovim-minimal ];
  flake.modules.homeManager.tui.imports = [ hmModules.neovim ];

  flake.modules.homeManager.neovim-minimal =
    {
      mylib,
      pkgs,
      config,
      ...
    }:
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        withRuby = false;
        withPython3 = false;
        viAlias = true;
        vimAlias = true;
        # init.lua 属于 config/；HM 的 initLua（catppuccin、语言表）经 wrapper 的 --cmd 先于它执行
        sideloadInitLua = true;
        plugins = [ pkgs.vimPlugins.nvim-treesitter ] ++ grammarPlugins pkgs baseGrammars;
      };

      xdg.configFile.nvim = mylib.mkConfigFile config ./config;
    };

  flake.modules.homeManager.neovim =
    {
      lib,
      mylib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.shelken.neovim;
      languages = builtins.attrValues (import ./_languages.nix pkgs);
      collect = field: lib.concatMap (lang: lang.${field} or [ ]) languages;
      byFiletype =
        field: lib.zipAttrsWith (_: lib.concatLists) (map (lang: lang.${field} or { }) languages);
      nixLanguages = {
        lsp = collect "lsp";
        formatters = byFiletype "formatters";
        linters = byFiletype "linters";
      };
    in
    {
      options.shelken.neovim = {
        minimal = mylib.mkBoolOpt false "只要 neovim-minimal：不装语言工具、LSP 与插件";
      };

      config = lib.mkIf (!cfg.minimal) {
        home.packages = collect "packages";

        programs.neovim = {
          initLua = "vim.g.nix_languages = ${lib.generators.toLua { } nixLanguages}";
          # 启动画面（config/lua/shelken/plugins.lua）用 chafa 渲染 gif
          extraPackages = [ pkgs.chafa ];
          plugins =
            with pkgs.vimPlugins;
            grammarPlugins pkgs (lib.subtractLists baseGrammars (collect "grammars"))
            ++ [
              nvim-lspconfig
              SchemaStore-nvim
              blink-cmp
              friendly-snippets
              conform-nvim
              nvim-lint
              snacks-nvim
              grug-far-nvim
              gitsigns-nvim
              which-key-nvim
              mini-icons
              mini-surround
              flash-nvim
              yazi-nvim
            ];
        };
      };
    };
}
