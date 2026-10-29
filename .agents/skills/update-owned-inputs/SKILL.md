---
name: update-owned-inputs
description: 更新、修改或同步自身维护的外部 input 或其上游源码仓库时使用（如 dotfiles.nix、secrets.nix、dot-astro-nvim 等），指导先改上游推送、等待联动 Action 完成后回当前仓库更新 flake.lock 并验证
---

# 外部 input 工作流

## 先确认仓库

先检查当前项目 `flake.nix` 里属于用户自己维护的 input
需要本地源码时，统一先在 `~/Code` 中检索并确认对应仓库，不预先假定路径

## 项目一句话说明

- `dot-astro-nvim`：个人 AstroNvim 配置仓库，作为 `dotfiles.nix` 的上游源码
- `dotfiles.nix`：将个人配置仓库封装为 flake packages，当前项目通过它获取上游源码
- `secrets.nix`：个人 secrets 仓库，当前项目直接引用
- `rime-auto-deploy`：rime 输入法配置仓库

## Action 一句话说明

- `dot-astro-nvim` 的 `sync upstream trigger`：推送至 `main` 后触发 `dotfiles.nix` 的 `sync-upstream.yml`，自动更新对应 input 的 `flake.lock` 并提交
- `dotfiles.nix` 的 `sync-upstream.yml`：接收 input 名称，执行 `nix flake lock --update-input` 并自动提交 `flake.lock`
- `secrets.nix`：通常无联动 action

## 参考流程

1. 从 `flake.nix` 确认本次修改的目标外部 input
2. 在 `~/Code` 搜索并定位对应上游仓库
3. 阅读相关文件后进行最小修改
4. 使用上游仓库自身的验证方式进行本地测试
5. 检查 git diff
6. 提交并推送至上游仓库
7. 若该仓库配置了联动 action，等待 action 执行完毕
8. 返回当前项目执行 `just upp <input>` 更新 `flake.lock`
9. 按影响范围验证当前项目：
   - 仅影响 Home Manager：执行 `just hm`
   - 影响 nix-darwin 或 NixOS 系统层：执行 `just sw`
10. 检查 `flake.lock` 的 diff 并提交当前项目

## 例子

### 改 `dot-astro-nvim`

1. 在 `~/Code` 搜索并定位 `dot-astro-nvim` 仓库
2. 修改源码并完成本地测试
3. 提交并推送至远程
4. 等待 `dot-astro-nvim` 的 action 执行完成
5. 等待 `dotfiles.nix` 触发的 action 执行完成
6. 返回当前项目执行 `just upp dotfiles`
7. 依据影响范围执行 `just hm` 或 `just sw`
8. 检查 `flake.lock` diff 并提交当前项目

## 不要这样做

- 禁止跳过上游仓库直接手动编辑当前项目的 `flake.lock`
- 禁止更新 lock 后未经构建验证直接提交

## 一句话记忆版

先在 `~/Code` 找到上游仓库，修改并推送，等待关联 action 完成，返回当前项目执行 `just upp <input>`，使用 `just hm` 或 `just sw` 验证后提交
