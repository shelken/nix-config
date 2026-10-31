---
name: nix2mise
description: 把项目的 nix flake 开发环境迁移到 mise,覆盖工具版本、环境变量、虚拟环境、prek(替代 pre-commit)和 shell 集成。
disable-model-invocation: true
---

# nix2mise

把项目 devShell 从 nix flake 迁移到 mise。mise 用 `mise.toml` 管理工具版本和环境变量,通过 shell integration(如 nix-config 的 `programs.mise.enableZshIntegration`)按目录自动加载。它不依赖 flake.lock 锁定的整条 nixpkgs 依赖链:升级单个工具只下载该工具,不像 `nix flake update` 动辄连锁重下 1G+。

## 迁移前确认

**安装前必须与用户确认执行方式。** 方案确认后,再问清是:

- 仅写配置:只创建/修改 mise.toml 等文件,不执行 `mise install`/`mise run setup`/`prek run`,安装验证由用户手动跑
- 连带安装验证:写完配置直接执行安装和端到端验证

用户未明确前,默认只写配置,停下等用户确认,不得擅自安装。

迁移前必须读完目标项目的 `flake.nix`,逐项识别它承担的职责,并逐一找替代。flake.nix 通常承担这些职责:

| flake.nix 职责 | mise 替代 | 说明 |
|---|---|---|
| `devShells.packages` 装工具 | `mise.toml` 的 `[tools]` | 版本规则见第 1 步 |
| `shellHook` 设环境变量 | `mise.toml` 的 `[env]` | 如控制包管理器行为的开关变量 |
| `shellHook` 创建+激活虚拟环境 | `[env]` 的 `_.python.venv` 等 | mise 原生支持各语言 venv 自动创建激活 |
| `shellHook` 跑依赖同步 | mise task | 按需 `mise run sync`,不每次进目录都跑 |
| git-hooks.nix 生成 pre-commit 配置 | 手写静态 `.pre-commit-config.yaml` | 不再生成,直接进版本库 |
| git-hooks.nix 自动安装 git hook | mise task(`prek install`) | 首次手动跑一次 |
| git-hooks.nix 设 `core.hooksPath` | 清除该配置 | 钩子装到默认 `.git/hooks`;nix 残留常用相对路径,清掉最稳 |

## SOP

### 1. 装工具到 mise.toml

读完 flake.nix 的 `packages` 列表,逐个用 `which -a <tool>` 确认当前系统是否已经提供,再决定归属。**完成标准:原 flake 的每个 devShell 工具都有归属,项目 `mise.toml` 的 `[tools]` 只声明系统没有的工具。**

三类归属:

1. **系统已提供**:`which -a <tool>` 命中的是 nix-config 共享工具表(如 `prek`、`bun`、`omp`)或全局 mise 装的版本,项目侧不声明,直接用系统版本
2. **系统没有、mise 有 backend**:写进项目 `mise.toml`
3. **系统没有、mise 也装不了**:交给系统包管理器(Homebrew/Home Manager),在 README 说明

系统已提供的工具不在项目里重复声明:版本跟着 nix-config 走,重复声明只会把项目锁在旧版本上。只有项目需要 pinned 版本或严格版本稳定时,才在项目里声明,并写明理由。

查 backend 和最新版本:

```bash
mise registry <tool>      # 查可用 backend(aqua/github/asdf/core/pipx 等)
mise ls-remote <tool>     # 查版本号,选最新稳定版
```

**mise 找不到的工具,先 web 搜索再下结论**:`mise registry` 查不到不等于 mise 装不了,查空后必须继续搜索。用 `web_search` 搜「`<tool> mise plugin`」「`<tool> asdf plugin`」「`<tool> install mise`」等,确认是否真无 backend,有无社区插件或 aqua/github/pipx 等通用 backend 可用;有多个可选方案时比较后选最稳的。只有搜索也确认没有可用方案的工具,才归入第 3 类交给 Homebrew/Home Manager。

写入 `mise.toml`。所有工具用具体版本号,不写 `latest`,保证可复现;升级时手动改:

```toml
[tools]
<tool-a> = "<具体版本号>"
<tool-b> = "<具体版本号>"
```

`min_version` 只在项目实际依赖某个 mise 版本特性时写,不写就没有下限要求。

**不写进 `[tools]` 的两类**:系统已提供的工具(第 1 类,如 `prek`);mise 生态覆盖差的工具(如设备通信、GUI 应用、Google/Apple 自托管分发的二进制),交给系统包管理器(Homebrew/Home Manager),在 README 说明。mise 的 aqua/github backend 依赖标准分发渠道,覆盖不到后一类工具,plugin 方案往往绕且不稳。判断标准:该工具是否需要「项目级版本锁定」;不需要则不进 mise。

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
run = ["<依赖同步命令>", "prek install"]   # 按项目实际填充;钩子类型见第 5 步

[tasks.sync]
description = "同步依赖"
run = "<依赖同步命令>"
```

**换掉旧钩子**:`prek install` 遇到已有 `.git/hooks/pre-commit`(pre-commit 或 git-hooks.nix 装的)会把它挪成 `<hook>.legacy`,并让新钩子和旧钩子同时跑。先验证新钩子无误,再 `prek install --force` 切干净;切早了用 `prek uninstall` 还原。

### 4. 启用 mise shell integration

mise 通过 shell integration 按目录自动加载 `mise.toml`。项目侧不需要 `.envrc` 等入口文件,项目根有 `mise.toml` 即可。**完成标准:进含 `mise.toml` 的目录后,工具版本/env/虚拟环境自动切换。**

若用 nix-config 管理 shell,在 home-manager 配置里启用:

```nix
programs.mise = {
  enable = true;
  enableZshIntegration = true;   # 或 enableBashIntegration
};
```

这会在 shell 初始化时注入 `eval "$(mise activate zsh)"`,由 mise 的 `chpwd` 钩子在进目录时自动加载项目配置。

### 5. 手写 .pre-commit-config.yaml

把原 git-hooks.nix 生成的配置转成手写 YAML,由 `prek` 执行。**完成标准:所有 hook 配置逻辑与原生成物一致,格式为可读 YAML,纯文本 hook 用 `repo: builtin`,其余通用 hook 用标准远端源。**

原生成物是 JSON 且带 `DO NOT MODIFY`,迁移后改为可读 YAML。保持 YAML:prek 也认 `prek.toml`,但 YAML 是与上游 pre-commit 的双向出口(`repo: builtin` 是 prek 扩展,用了它这份配置就只归 prek 跑)。

- **纯文本 hook(优先 `repo: builtin`)**:基础文本与格式检查(`end-of-file-fixer`、`trailing-whitespace`、`check-merge-conflict`、`check-json`/`check-toml`/`check-yaml`、`check-added-large-files`)写成 `repo: builtin`,离线可用,不克隆仓库也不建环境:

  ```yaml
  repos:
    - repo: builtin
      hooks:
        - id: trailing-whitespace
        - id: end-of-file-fixer
  ```

- **标准远端 hook**:需要语言环境的检查(如 `ruff`、`shellcheck`)用官方标准远端源(`repo: https://github.com/...` 并锁定 `rev: <版本号>`),由 prek 管理其独立隔离环境。`pre-commit/pre-commit-hooks` 的远端写法照旧可用 —— prek 识别后走 Rust 原生实现,`rev` 与整份配置在上游 pre-commit 下仍然合法;行为有疑问时用 `PREK_NO_FAST_PATH=1 prek run --all-files` 与远端实现对照。**严禁**为了在本地跑基础 hook 而在 `mise.toml` 中引入 `pipx:pre-commit-hooks` 等外围包装工具污染项目配置。
- **本地系统 hook(仅限复用项目主工具)**:仅当 hook 执行的是项目自身的主构建/检查工具(如 `cargo clippy`、`golangci-lint`、项目既有 npm scripts),且该工具已由 `mise.toml` 的 `[tools]` 或项目主包管理器管理时,才使用 `repo: local` + `language: system`。
- 逐条核对原 hook 的 `entry`/`files`/`pass_filenames` 等字段,原样保留语义;涉及 `--staged` 等不接收文件名的命令,保持 `pass_filenames: false`。
- **hook 阶段**:`stages` 含 `pre-push` 等非 `pre-commit` 阶段时,在配置顶层写 `default_install_hook_types`,让 `prek install` 一次装齐:

  ```yaml
  default_install_hook_types: [pre-commit, pre-push]
  ```

  给已装好钩子的仓库补装,用 `prek install --hook-type pre-push`。

### 6. 清理 nix 残留

删除 flake 文件与 direnv 残留,清理 git 和 .gitignore。**完成标准:无 flake.nix/flake.lock/.envrc/.direnv;原被 gitignore 的生成物(如 `.pre-commit-config.yaml`)移出忽略;`core.hooksPath` 已 unset。**

```bash
rm flake.nix flake.lock
rm .envrc                        # 内容为 use flake 的 direnv 入口,若被 git 跟踪需 git rm --cached
rm -rf .direnv/                  # direnv 自动生成的缓存目录,连同 .gitignore 里的 .direnv 条目一起清掉
git config --unset-all core.hooksPath   # git-hooks.nix 残留;相对路径会让 prek install 装错位置,清掉走默认 .git/hooks
```

检查 `.gitignore`,把「原 nix 生成物」从忽略列表移除(`.direnv`、`.pre-commit-config.yaml` 等,改手写后要进版本库)。

### 7. 验证

端到端验证整套环境。**完成标准:下方五项全部通过。**

```bash
mise trust                  # 首次信任 mise.toml
mise install                # 装所有工具
mise run setup              # 初始化
prek run                    # 全部 hook Passed(若项目配了 hook)
prek run --all-files        # 存量文件同样 Passed
```

工具来源验证(项目声明的工具应指向项目 mise 安装路径,系统共享工具指向全局 mise 安装路径,都不该命中旧 nix 路径):

```bash
which <tool>                # 逐个核对原 flake 装的工具
which -a prek               # 系统共享工具:项目里没有 prek 条目,命中的是全局 mise
```

## 日常使用

### 首次进入项目

mise.toml 未信任时,所有工具显示 "not installed",先 `mise trust`。

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

### 有用命令

```bash
mise current              # 查当前激活的工具及版本
mise ls                   # 查已装工具
mise use <tool>@<ver>     # 装工具并写入 mise.toml
mise untrust              # 取消信任配置
```
