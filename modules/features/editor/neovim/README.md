# Neovim

插件、语言工具、treesitter 语法都由 Nix 提供，不在运行时下载；`flake.lock` 决定版本，回滚跟随 Home Manager generation。

## 两层

| 层               | 谁有                                         | 内容                                                                                               |
| ---------------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `neovim-minimal` | 所有主机（core，含服务器）                   | nvim、`config/` 的选项、`baseGrammars` 的 treesitter 高亮、内置 `autocomplete`（当前 buffer 的词） |
| `neovim`         | tui 及以上，`shelken.neovim.minimal = false` | 再加 `_languages.nix` 的工具、LSP、其余语法和插件；blink.cmp 接管补全                              |

两层共用一份 `config/`：`init.lua` 只在 Nix 注入了 `vim.g.nix_languages`（完整层）时加载 `lsp.lua` 与 `plugins.lua`。

## 文件

| 文件             | 作用                                                        |
| ---------------- | ----------------------------------------------------------- |
| `default.nix`    | 两层的 HM 模块；`baseGrammars` 决定没有语言工具时也有的高亮 |
| `_languages.nix` | 语言表：每种语言的工具包、LSP、formatter、linter、语法      |
| `config/`        | `~/.config/nvim`，普通 Lua，经 `mylib.mkConfigFile` 部署    |

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

沿用 AstroNvim 默认（`<leader>ff` / `<leader>fw` / `<leader>fo` / `<leader>f<CR>` / `<leader>la` / `<leader>lr` / `<leader>lf` / `<leader>ls` / `<leader>lD` / `<leader>gg` / `<leader>e`、`]g` / `[g`、`gd` / `gl`、`H` / `L`），按下空格稍等，which-key 会列出全部绑定。Neovim 自带的 `grn` / `gra` / `grr` / `gri` / `gO` / `K` 也可用，见 `:help lsp-defaults`。不依赖插件的键位在 `keymaps.lua`，minimal 层也有。

## 启动画面

snacks.dashboard 的 terminal 区块运行 `chafa`，把 `config/assets/mio.gif` 实时渲染成盲文字符画（动画）。换图只需替换该文件。
