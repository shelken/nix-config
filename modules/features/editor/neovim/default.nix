# Neovim
#   neovim-minimal（core）：所有主机都有的 nvim 本体与 vi/vim 别名
#   neovim（tui 及以上）：插件、语言工具与 config/；shelken.neovim.minimal = true 时只留本体
# 语言工具链见 _languages.nix，Lua 配置见 config/
{ config, ... }:
let
  hmModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.core.imports = [ hmModules.neovim-minimal ];
  flake.modules.homeManager.tui.imports = [ hmModules.neovim ];

  flake.modules.homeManager.neovim-minimal = {
    programs.neovim = {
      enable = true;
      withRuby = false;
      withPython3 = false;
      viAlias = true;
      vimAlias = true;
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
        minimal = mylib.mkBoolOpt false "只装 nvim 本体，不带插件、语言工具和配置";
      };

      config = lib.mkIf (!cfg.minimal) {
        home.packages = collect "packages";

        programs.neovim = {
          defaultEditor = true;
          # init.lua 属于 config/；initLua 经 wrapper 的 --cmd 先于它执行，把语言表交给 Lua
          sideloadInitLua = true;
          initLua = "vim.g.nix_languages = ${lib.generators.toLua { } nixLanguages}";
          plugins = with pkgs.vimPlugins; [
            (nvim-treesitter.withPlugins (grammars: map (name: grammars.${name}) (collect "grammars")))
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

        xdg.configFile.nvim = mylib.mkConfigFile config ./config;
      };
    };
}
