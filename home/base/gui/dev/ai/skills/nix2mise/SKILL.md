---
name: nix2mise
description:
  将项目的 nix flake 开发环境迁移到 mise。当用户说「flake 转 mise」「nix 换
  mise」「用 mise 替代 flake/nix」「去掉 nix 依赖」或讨论 devShell 工具管理的替代方案时
  使用。覆盖工具版本管理、环境变量、虚拟环境、pre-commit、shell 集成的通用迁移流程。
disable-model-invocation: true
---

# nix2mise

把项目 devShell 从 nix flake 迁移到 mise。mise 用 `mise.toml` 管工具版本和环境变量,通过 shell integration(如 nix-config 的 `programs.mise.enableZshIntegration`)按目录自动加载;不再依赖 flake.lock 锁定的整条 nixpkgs 依赖链,升级单个工具只下那个工具,避免 `nix flake update` 动辄重下 1G+ 的连锁下载。

## 迁移前确认

迁移前必须读完目标项目的 `flake.nix`,逐项识别它承担的职责。flake.nix 通常做这些事,迁移时逐一找替代:

| flake.nix 职责 | mise 替代 | 说明 |
|---|---|---|
| `devShells.packages` 装工具 | `mise.toml` 的 `[tools]` | 每个工具指定版本号,不写 `latest` |
| `shellHook` 设环境变量 | `mise.toml` 的 `[env]` | 如控制包管理器行为的开关变量 |
| `shellHook` 创建+激活虚拟环境 | `[env]` 的 `_.python.venv` 等 | mise 原生支持各语言 venv 自动创建激活 |
| `shellHook` 跑依赖同步 | mise task | 按需 `mise run sync`,不每次进目录都跑 |
| git-hooks.nix 生成 pre-commit 配置 | 手写静态 `.pre-commit-config.yaml` | 不再生成,直接进版本库 |
| git-hooks.nix 自动安装 git hook | mise task | 首次手动跑一次 |
| git-hooks.nix 设 `core.hooksPath` | 清除该配置 | pre-commit 用默认 `.git/hooks` |

## SOP

### 1. 装工具到 mise.toml

读完 flake.nix 的 `packages` 列表,逐个查 mise registry 确认 backend,再写入 `mise.toml`。**完成标准:`mise.toml` 的 `[tools]` 覆盖原 flake 所有 devShell 工具(系统级工具除外)。**

查 backend 和最新版本:

```bash
mise registry <tool>      # 查可用 backend(aqua/github/asdf/core/pipx 等)
mise ls-remote <tool>     # 查版本号,选最新稳定版
```

写入 `mise.toml`,所有工具用具体版本号:

```toml
min_version = "2024.9.5"

[tools]
<tool-a> = "<具体版本号>"
<tool-b> = "<具体版本号>"
# 若原项目用 git-hooks.nix,需额外补 pre-commit 本体
pre-commit = "<版本号>"
```

**系统级工具不进 mise**:不随项目版本变化、或 mise 生态覆盖差的工具(如设备通信、GUI 应用、Google/Apple 自托管分发的二进制),交给系统包管理器(Homebrew/Home Manager),在 README 说明。判断标准:该工具是否需要「项目级版本锁定」;不需要则不进 mise。

### 2. 配置环境与虚拟环境

把 flake.nix 的 `shellHook` 环境变量和虚拟环境逻辑迁到 `mise.toml`。**完成标准:`[env]` 含原所有环境变量,虚拟环境配置正确。**

```toml
[env]
<ENV_VAR> = "<value>"
_.python.venv = { path = ".venv", create = true }   # Python 项目
# 其他语言同理,mise 原生支持各自 venv/node_modules 等自动管理
```

### 3. 定义 mise task

把 flake `shellHook` 的初始化动作封装成 task。**完成标准:相关 task 注册成功,`mise tasks` 能列出。**

```toml
[tasks.setup]
description = "首次环境初始化"
run = ["<依赖同步命令>", "pre-commit install"]   # 按项目实际填充

[tasks.sync]
description = "同步依赖"
run = "<依赖同步命令>"
```

### 4. 启用 mise shell integration

mise 通过 shell integration 按目录自动加载 `mise.toml`,无需额外目录级入口文件。**完成标准:进含 `mise.toml` 的目录后,工具版本/env/虚拟环境自动切换。**

若用 nix-config 管理 shell,在 home-manager 配置里启用:

```nix
programs.mise = {
  enable = true;
  enableZshIntegration = true;   # 或 enableBashIntegration
};
```

这会在 shell 初始化时注入 `eval "$(mise activate zsh)"`,mise 的 `chpwd` 钩子负责进目录时自动加载项目配置。项目侧不需要 `.envrc` 或任何入口文件,只要项目根有 `mise.toml` 即可。

### 5. 手写 .pre-commit-config.yaml

把原 git-hooks.nix 生成的配置转成手写 YAML。**完成标准:所有 hook 配置逻辑与原生成物一致,格式为可读 YAML。**

原生成物是 JSON 且带 `DO NOT MODIFY`,迁移后改为可读 YAML。所有 hook 用 `language: system`(依赖 mise 提供的工具链)。逐条核对原 hook 的 `entry`/`files`/`pass_filenames` 等字段,原样保留语义;涉及 `--staged` 等不接收文件名的命令,保持 `pass_filenames: false`。

### 6. 清理 nix 残留

删除 flake 文件,清理 git 和 .gitignore。**完成标准:无 flake.nix/flake.lock;原被 gitignore 的生成物(如 `.pre-commit-config.yaml`)移出忽略;`core.hooksPath` 已 unset。**

```bash
rm flake.nix flake.lock
git config --unset-all core.hooksPath   # git-hooks.nix 残留,不清理会致 pre-commit install 拒绝
```

检查 `.gitignore`,把「原 nix 生成物」从忽略列表移除(改手写后要进版本库)。

### 7. 验证

端到端验证整套环境。**完成标准:下方四项全部通过。**

```bash
mise trust                  # 首次信任 mise.toml
mise install                # 装所有工具
mise run setup              # 初始化
pre-commit run --all-files  # 全部 hook Passed(若项目用 pre-commit)
```

工具来源验证(应指向 mise 安装路径,而非系统/旧 nix 路径):

```bash
which <tool>                # 逐个核对原 flake 装的工具
```

## 日常使用

### 首次进入项目

```bash
mise trust          # 信任 mise.toml
mise install        # 装工具
mise run setup      # 初始化(装依赖 + 装 git hook)
```

### 更新工具版本

改 `mise.toml` 里版本号,然后:

```bash
mise install        # 装新版本,旧版本保留可回退
```

升级单个工具只下载该工具,不像 `nix flake update` 会连锁重下整条 nixpkgs 依赖链。

### 有用命令

```bash
mise current              # 查当前激活的工具及版本
mise ls                   # 查已装工具
mise ls-remote <tool>     # 查远程可用版本
mise use <tool>@<ver>     # 装工具并写入 mise.toml
mise tasks                # 列出所有 task
mise run <task>           # 执行 task
mise registry <tool>      # 查工具的 backend
mise trust / mise untrust # 信任/取消信任配置
```

## 踩坑记录

- **`mise trust`**:首次进入 mise.toml 未信任,所有工具显示 "not installed",需 `mise trust`。
- **系统级工具不进 mise**:设备通信、GUI 应用、厂商自托管二进制等,mise 的 aqua/github backend 覆盖不到(它们依赖标准分发渠道),plugin 方案往往绕且不稳。判断标准是「是否需要项目级版本锁定」,不需要则交给系统包管理器。
- **版本号写死**:用具体版本号而非 `latest`,保证可复现;升级时手动改。
