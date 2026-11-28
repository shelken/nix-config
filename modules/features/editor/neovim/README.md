# Neovim

插件、语言工具与 treesitter 语法均由 Nix 提供，不在运行时下载；版本由 `flake.lock` 锁定，回滚跟随 Home Manager generation

全员统一安装预编译 `pkgs.neovim-unwrapped`，经无 CC 的 `xdg.dataFile` 挂载 packpath 与 `nix_config.lua`；纯 Lua 插件直取源码（`.src`），有构建步骤的插件及 treesitter parser 走官方二进制缓存，避免 `programs.neovim` 与 `buildVimPlugin` 在更新 `flake.lock` 后触发 `stdenv`/`gcc` 本地构建

`neovim-minimal`（`core`，所有主机）只保留 Catppuccin 主题与运维常用 treesitter 高亮；`neovim`（`tui` 及以上，可通过 `shelken.neovim.minimal = true` 退回 minimal）补齐 UI、补全、LSP、语言工具与全量语法
