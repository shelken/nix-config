# Neovim
#   neovim-minimal（core，含服务器）：nvim、config/、全部语法高亮、外观与补全类插件；不装语言工具
#   neovim（tui 及以上）：再加语言工具、LSP 与功能类插件；shelken.neovim.minimal = true 时不加
# 语言工具链见 _languages.nix，Lua 配置见 config/
{ config, ... }:
let
  hmModules = config.flake.modules.homeManager;

  languagesOf = pkgs: builtins.attrValues (import ./_languages.nix pkgs);
  collect = pkgs: field: pkgs.lib.concatMap (lang: lang.${field} or [ ]) (languagesOf pkgs);

  # catppuccin 的 auto_integrations 只认 vim.pack / lazy / pckr，识别不了 Nix 放进 packpath 的插件，需显式列出
  catppuccinIntegrations =
    lib: names:
    lib.genAttrs names (_: {
      enabled = true;
    });
in
{
  flake.modules.homeManager.core.imports = [ hmModules.neovim-minimal ];
  flake.modules.homeManager.tui.imports = [ hmModules.neovim ];

  flake.modules.homeManager.neovim-minimal =
    {
      lib,
      mylib,
      pkgs,
      config,
      ...
    }:
    let
      ts = pkgs.vimPlugins.nvim-treesitter;
      # 同 nvim-treesitter.withPlugins：parser 与高亮 queries 是两个插件，缺 queries 就没有高亮
      grammars = lib.concatMap (
        name: [ ts.grammarPlugins.${name} ] ++ lib.optional (ts.queries ? ${name}) ts.queries.${name}
      ) (collect pkgs "grammars");
    in
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
        # 配置见 config/lua/shelken/ui.lua
        plugins =
          with pkgs.vimPlugins;
          [
            nvim-treesitter
            noice-nvim
            nui-nvim
            blink-cmp
            markview-nvim
            mini-icons
          ]
          ++ grammars;
      };

      xdg.configFile.nvim = mylib.mkConfigFile config ./config;

      catppuccin.nvim.settings = {
        # 透出终端背景（原 AstroNvim 配置同样开启）
        transparent_background = true;
        integrations = catppuccinIntegrations lib [
          "blink_cmp"
          "markview"
          "mini"
          "noice"
        ];
      };
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
      byFiletype =
        field: lib.zipAttrsWith (_: lib.concatLists) (map (lang: lang.${field} or { }) (languagesOf pkgs));
      nixLanguages = {
        lsp = collect pkgs "lsp";
        formatters = byFiletype "formatters";
        linters = byFiletype "linters";
      };
    in
    {
      options.shelken.neovim = {
        minimal = mylib.mkBoolOpt false "只要 neovim-minimal：不装语言工具、LSP 与功能类插件";
      };

      config = lib.mkIf (!cfg.minimal) {
        home.packages = collect pkgs "packages";

        programs.neovim = {
          initLua = "vim.g.nix_languages = ${lib.generators.toLua { } nixLanguages}";
          # 启动画面（config/lua/shelken/plugins.lua）用 chafa 渲染 gif
          extraPackages = [ pkgs.chafa ];
          # 配置见 config/lua/shelken/{lsp,plugins}.lua
          plugins = with pkgs.vimPlugins; [
            nvim-lspconfig
            SchemaStore-nvim
            friendly-snippets
            conform-nvim
            nvim-lint
            snacks-nvim
            grug-far-nvim
            gitsigns-nvim
            which-key-nvim
            mini-surround
            flash-nvim
            yazi-nvim
          ];
        };

        catppuccin.nvim.settings.integrations = catppuccinIntegrations lib [
          "flash"
          "gitsigns"
          "grug_far"
          "snacks"
          "which_key"
        ];
      };
    };
}
