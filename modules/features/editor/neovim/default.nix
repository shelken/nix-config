{ config, ... }:
let
  hmModules = config.flake.modules.homeManager;

  coreGrammars = [
    "nix"
    "bash"
    "json"
    "yaml"
    "toml"
    "dockerfile"
    "diff"
  ];

  languagesOf = pkgs: builtins.attrValues (import ./_languages.nix pkgs);
  collect = pkgs: field: pkgs.lib.concatMap (lang: lang.${field} or [ ]) (languagesOf pkgs);

  collectDeps =
    lib: list:
    let
      expand = p: [ p ] ++ lib.concatMap expand (p.dependencies or [ ]);
    in
    lib.unique (lib.concatMap expand list);

  isPurePlugin =
    p:
    (p.patches or [ ]) == [ ]
    && (p.buildPhase or ":") == ":"
    && (p.preInstall or "") == ""
    && (p.postInstall or "") == ""
    && (p.postPatch or "") == ""
    && !(p ? sourceRoot)
    && p ? src;

  pluginSource = p: if isPurePlugin p then p.src else p;
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
      cfg = config.shelken.neovim;
      ts = pkgs.vimPlugins.nvim-treesitter;
      grammarNames = lib.unique cfg.grammars;
      queryDrvs = collectDeps lib (
        lib.concatMap (name: lib.optional (ts.queries ? ${name}) ts.queries.${name}) grammarNames
      );
      grammarsDir = pkgs.symlinkJoin {
        name = "nvim-treesitter-grammars";
        paths = map (name: ts.grammarPlugins.${name}) grammarNames ++ queryDrvs;
      };

      allPlugins = collectDeps lib cfg.plugins;
      pluginEntries = [
        {
          name = "catppuccin-nvim";
          path = config.catppuccin.sources.nvim;
        }
        {
          name = "nvim-treesitter-grammars";
          path = grammarsDir;
        }
      ]
      ++ map (p: {
        name = p.pname or (lib.getName p);
        path = pluginSource p;
      }) allPlugins;

      nvimAliases = pkgs.linkFarm "nvim-aliases" [
        {
          name = "bin/vi";
          path = "${pkgs.neovim-unwrapped}/bin/nvim";
        }
        {
          name = "bin/vim";
          path = "${pkgs.neovim-unwrapped}/bin/nvim";
        }
      ];
    in
    {
      options.shelken.neovim = {
        minimal = mylib.mkBoolOpt false "只要 neovim-minimal：不装语言工具、LSP 与功能类插件";
        grammars = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Treesitter 语法解析器列表";
        };
        plugins = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Neovim 插件列表";
        };
        languages = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = null;
          description = "传给 Lua 的 LSP/formatter/linter 语言表，非 null 时启用完整层";
        };
      };

      config = {
        catppuccin.nvim.enable = false;
        shelken.neovim.grammars = coreGrammars;

        home = {
          packages = [
            pkgs.neovim-unwrapped
            nvimAliases
          ];
          sessionVariables = {
            EDITOR = "nvim";
            VISUAL = "nvim";
          };
        };

        xdg.configFile.nvim = mylib.mkConfigFile config ./config;

        xdg.dataFile = {
          "nvim/site/pack/nix/start".source = pkgs.linkFarm "nvim-pack-start" pluginEntries;
          "nvim/site/lua/nix_config.lua".text = "return ${
            lib.generators.toLua { } {
              flavor = config.catppuccin.flavor;
              languages = cfg.languages;
            }
          }";
        };
      };
    };

  flake.modules.homeManager.neovim =
    {
      lib,
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
      config = lib.mkIf (!cfg.minimal) {
        home.packages = [ pkgs.chafa ] ++ collect pkgs "packages";

        shelken.neovim = {
          languages = nixLanguages;
          grammars = collect pkgs "grammars";
          plugins = with pkgs.vimPlugins; [
            nvim-treesitter
            noice-nvim
            nui-nvim
            blink-cmp
            markview-nvim
            mini-icons
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
      };
    };
}
