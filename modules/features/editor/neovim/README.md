# Neovim

插件、语言工具与 treesitter 语法均由 Nix 提供，不在运行时下载；版本由 `flake.lock` 锁定，回滚跟随 Home Manager generation

`neovim-minimal`（所有主机）与 `neovim`（tui 及以上）共用 `config/`，拆分原则是不依赖外部命令的外观与补全进 minimal，依赖语言工具或 `rg` 等外部命令的留在完整层
