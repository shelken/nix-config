---
name: update-owned-inputs
description:
  当用户要更新、修改、同步自己维护的外部 input 或其上游源码仓库时使用，尤其适用于
  `dotfiles.nix`、`secrets.nix`、`dot-astro-nvim`等，以及“先改上游再回当前项目更新 flake.lock”“等
  action 跑完再 upp”这类场景。
---

# 外部 input 工作流

## 先确认仓库

先看当前项目 `flake.nix` 里属于用户自己维护的 input。  
需要本地源码时，统一先在 `~/Code` 里搜索并确认对应仓库，不要先假定路径。

## 项目一句话说明

- `dot-astro-nvim`：个人 AstroNvim 配置仓库，作为 `dotfiles.nix` 的上游源码。
- `dotfiles.nix`：把个人配置仓库封装成 flake packages，当前项目通过它拿这些上游源码。
- `secrets.nix`：个人 secrets 仓库，当前项目直接引用它。
- `rime-auto-deploy`：rime 输入法配置

## Action 一句话说明

- `dot-astro-nvim` 的 `sync upstream trigger`：push 到 `main` 后触发 `dotfiles.nix` 的
  `sync-upstream.yml`，让 `dotfiles.nix` 自动更新对应 input 的 `flake.lock` 并提交。
- `dotfiles.nix` 的 `sync-upstream.yml`：接收一个 input 名，执行
  `nix flake lock --update-input`，然后自动提交 `flake.lock`。
- `secrets.nix`：通常没有联动 action。

## 参考流程

1. 从 `flake.nix` 确认这次改的是哪个外部 input。
2. 在 `~/Code` 搜索并确认对应上游仓库。
3. 读相关文件后做最小修改。
4. 用上游仓库自己的方式做本地检查或测试。
5. 检查 diff。
6. 提交并推送上游仓库。
7. 如果这个仓库有联动 action，就先等 action 跑完。
8. 回当前项目执行对应的 `just upp <input>` 更新 `flake.lock`。
9. 按影响范围验证当前项目：
   - 只影响 Home Manager：`just hm`
   - 影响 nix-darwin 或 NixOS 系统级：`just sw`
10. 检查 `flake.lock` diff 后提交当前项目。

## 例子

### 改 `dot-astro-nvim`

1. 先在 `~/Code` 搜索并确认 `dot-astro-nvim` 仓库。
2. 改源码并做本地测试。
3. 提交并推送。
4. 等 `dot-astro-nvim` 的 action 跑完。
5. 等 `dotfiles.nix` 被触发的 action 跑完。
6. 回当前项目执行 `just upp dotfiles`。
7. 根据影响范围执行 `just hm` 或 `just sw`。
8. 检查 `flake.lock` diff 并提交当前项目。

## 不要这样做

- 不要跳过上游仓库，直接手改当前项目 `flake.lock`。
- 不要更新 lock 后不验证就提交。

## 一句话记忆版

先在 `~/Code` 找上游仓库，改完并推送，等该等的 action，回当前项目执行 `just upp <input>`，再用
`just hm` 或 `just sw` 验证，最后提交当前项目。
