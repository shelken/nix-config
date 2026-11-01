# Neovim

插件、语言工具、treesitter 语法都由 Nix 提供，不在运行时下载；`flake.lock` 决定版本，回滚跟随 Home Manager generation。

## 两层

| 层               | 谁有                                         | 内容                                                                                                                                |
| ---------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `neovim-minimal` | 所有主机（core，含服务器）                   | nvim、选项与键位、`_languages.nix` 全部语法的高亮、外观与补全（noice 居中命令行、blink.cmp、markview、mini.icons）、透明 catppuccin |
| `neovim`         | tui 及以上，`shelken.neovim.minimal = false` | 再加语言工具、LSP / conform / nvim-lint 与功能类插件（snacks、gitsigns、which-key、flash、mini.surround、yazi、grug-far）           |

两层共用一份 `config/`：`init.lua` 总是加载 `options` / `keymaps` / `ui`，只在 Nix 注入了 `vim.g.nix_languages`（完整层）时加载 `lsp` / `plugins`。插件放哪层的原则：不依赖外部命令的外观与补全进 minimal，依赖语言工具或 rg 等命令的留在完整层。

## 文件

| 文件             | 作用                                                     |
| ---------------- | -------------------------------------------------------- |
| `default.nix`    | 两层的 HM 模块；各层插件列表与 catppuccin 集成           |
| `_languages.nix` | 语言表：每种语言的工具包、LSP、formatter、linter、语法   |
| `config/`        | `~/.config/nvim`，普通 Lua，经 `mylib.mkConfigFile` 部署 |

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
