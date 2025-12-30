# AGENTS.md

## 常用命令

```bash
# 构建并应用配置 (macOS/NixOS)
just sw                  # 或 just switch

# 仅构建不应用
just b                   # 或 just rebuild

# 调试模式构建
just bd                  # 或 just rebuild-debug

# 格式化代码
just fmt                 # 运行 deadnix 和 nix fmt

# 远程部署 (使用 Colmena)
just deploy <tag> <mach> # 例如: just deploy pve156 shelken@192.168.6.156

# 更新 flake 输入
just up                  # 更新所有输入
just upp <input>         # 更新指定输入

# 垃圾回收
just gc                  # 清理无用的包（默认保留0h）
just gc-all              # 清理所有历史

# 进入 REPL 调试
just repl <host>         # 例如: just repl sakamoto

# 搜索包
just search <pkg>        # 搜索 nixpkgs
```

**注意**: 首次使用需要在 `.env` 文件中设置 `PROFILE=<hostname>`。

## Git 提交规则（最高优先级）

- 使用 `Conventional Commits` 规范：`<type>[optional scope]: <description>`
- 提交信息应分点简洁，**标题英文，内容中文**

## 架构概览

这是一个基于 Nix Flakes 的多平台配置仓库，管理 macOS (nix-darwin) 和 Linux (NixOS)。

- **入口**: `flake.nix`
- **模块化**:
  - `modules/base`: 跨平台共享配置
  - `modules/darwin`: macOS 特有配置
  - `modules/nixos`: Linux 特有配置
  - `home/`: Home Manager 配置，按平台 (`darwin`/`linux`) 划分
- **机器配置**: `hosts/<hostname>/default.nix`
- **变量与库**:
  - `vars/`: 全局变量（用户名、邮箱等）
  - `lib/`: 自定义函数（`mylib.scanPaths`, `mylib.relativeToRoot` 等）

## 关键约定

- **软件源**: 使用 `nvfetcher` 管理非 nixpkgs 源
- **秘密管理**: 引用外部 `secrets` flake（通过 sops-nix）
- **Pre-commit hooks**: 使用 `nixfmt-rfc-style`, `typos`, `prettier` 自动格式化
