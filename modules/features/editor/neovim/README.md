# Neovim

插件、语言工具、treesitter 语法都由 Nix 提供，不在运行时下载；`flake.lock` 决定版本，回滚跟随 Home Manager generation。

## 文件

| 文件             | 作用                                                                                                |
| ---------------- | --------------------------------------------------------------------------------------------------- |
| `default.nix`    | 两个 HM 模块：`neovim-minimal`（core，只有 nvim 本体）和 `neovim`（tui 及以上，插件 + 工具 + 配置） |
| `_languages.nix` | 语言表：每种语言的工具包、LSP、formatter、linter、语法                                              |
| `config/`        | `~/.config/nvim`，普通 Lua，经 `mylib.mkConfigFile` 部署                                            |

## 加一门语言

只改 `_languages.nix`，加一个条目：

- `packages`：装进 PATH 的工具
- `lsp`：[nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/tree/master/lsp) 的配置名
- `formatters` / `linters`：filetype → [conform](https://github.com/stevearc/conform.nvim#formatters) / [nvim-lint](https://github.com/mfussenegger/nvim-lint#available-linters) 的名字
- `grammars`：nvim-treesitter 语法名

`default.nix` 把表拆成 `home.packages`、treesitter 插件和 `vim.g.nix_languages`；`config/lua/shelken/lsp.lua` 读后者，Lua 侧无需改动。LSP 需要额外 settings 时再在 `lsp.lua` 里写 `vim.lsp.config`。

## 加一个插件

`default.nix` 的 `programs.neovim.plugins` 加 `pkgs.vimPlugins.<名字>`，在 `config/lua/shelken/plugins.lua` 里 `setup`。

## 快捷键

`<leader>` 是空格。按下空格稍等，which-key 会列出全部绑定。LSP 用 Neovim 自带的 `grn` / `gra` / `grr` / `gri` / `gO` / `K`，见 `:help lsp-defaults`。
