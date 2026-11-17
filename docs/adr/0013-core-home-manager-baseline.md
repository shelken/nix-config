# core 的 Home Manager 部分同样只放基线

日期: 2026-11-18

ADR 0005 把 `core` 定为所有角色共有的基线，只清理了 NixOS 侧，Home Manager 侧仍按「每台机器都想用」加入功能：yazi（拉进 ffmpeg、resvg，独占约 330 MiB）、lazygit、tig、git-cliff、nix-tree 等随 `homeManager.core` 装到了每台服务器。现在 `homeManager.core` 只放登录后的 shell 环境（zsh、starship、git 配置、neovim-minimal、btop、zmx、fastfetch 等），交互工作台加入 `tui`。同一软件两层都要时，在一个文件里发布两个模块：精简的加入 `core`，其余加入 `tui`，如 `neovim-minimal` 与 `neovim`、`git` 与 `git-tools`。

NixOS 为本机交互默认开启的部分，服务器用不上，由只加入 `server` 的功能 `server-minimal` 关闭：registry 与 `NIX_PATH` 钉住的 nixpkgs 源码（约 200 MiB）、安装工具（`nixos-rebuild`、`nixos-enter` 等）、文档与 man。服务器只由 deploy-rs 推送，不在本机跑 `nix run nixpkgs#…` 或 `nixos-rebuild`

## 考虑过的替代方案

- **服务器不装 Home Manager**：能多省 zsh、starship 等，但 HM 接线在 `core`，要整体挪出，服务器上也没有统一的 shell 配置
- **为服务器另立 HM 角色，`core` 保持原样**：每个工作台功能都得声明「不进服务器」，与「功能声明加入哪个角色」的方向相反
- **导入 nixpkgs 的 `profiles/minimal.nix`**：它同时关掉 xdg、字体等不在本仓库掌控内的项，单独使用省得不多

## 后果

- 服务器上没有 `nixos-rebuild`、`nixos-enter`、`nixos-version`、`man`；需要救援工具的镜像变体自行打开，如 hk1box 的 U 盘镜像
- 服务器上的 `nix run nixpkgs#…` 改用全局 registry，联网拉取最新 nixpkgs
- fastfetch 不再经 mise 安装，全平台用 `fastfetch-unwrapped`：完整版会拉进图形依赖，darwin 上约 450 MiB
- 新功能加入 `homeManager.core` 前，先确认服务器登录后确实要用它
