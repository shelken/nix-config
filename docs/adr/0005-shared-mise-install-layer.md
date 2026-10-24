# 0005 共用 mise 安装层：跨 VM 共享工具安装与下载缓存

日期: 2026-10-23
状态: Accepted
关联: 修订 [ADR 0003](0003-shared-tool-single-declaration.md)（状态归置），依赖 [ADR 0002](0002-single-main-vm-execution-context.md)（单主 VM 执行上下文）；忙闲与插件规则由 [ADR 0006](0006-sandbox-razor.md) 进一步简化

## 背景

ADR 0003 把 mise 的安装状态（`installs`、下载缓存）归入各 VM 的数据盘（`/data`）。实测暴露两个问题：

1. **重复安装**：主 VM 数据盘坏掉/重建、一次性 e2e VM 启动时，mise 工具（bun、codex、oh-my-pi 等）要全部重新下载安装。下载量大、耗时长，且 OMP 插件（bun install）同样受累。
2. **上限指纹漂移**：若把宿主真实路径直接写进 VM 挂载配置，配置内容变化（如宿主用户名、路径调整）会改变上限指纹，导致复用中的 VM 被判定「上限不一致」触发重建。

## 决策

1. **宿主侧单一共用目录**：`~/Data/sandboxes/mise/aarch64-linux`，内含 `data/`（安装层，含 `installs/`、`downloads/`）与 `cache/`（下载/构建缓存）。路径取真实物理路径（非符号链接），挂载进所有 VM 时 msb 解析符号链接后仍指向同一目录。
2. **guest 固定挂载点**：所有 VM（主 VM、一次性 e2e VM、保留的 sb-default）中该目录一律挂到 `/opt/sandbox-mise`。**上限指纹只包含 guest 侧挂载声明 `/opt/sandbox-mise:rw`，不含宿主真实路径**——宿主路径变化不触发重建。
3. **读写分层**：挂载在 VM 层是读写（`sb sync` 需要写入安装层）；进入**执行上下文**（launcher bubblewrap 内）转为**只读绑定**——上下文内禁止任何安装/写入，工具消费只读使用，安装只允许经 `sb sync` 显式发生。运行上下文同时设置 `MISE_AUTO_INSTALL=0`、`MISE_NOT_FOUND_AUTO_INSTALL=0`。
4. **仍归各 VM 数据盘的状态**：`state`（mise 注册表状态）、`shims`（各 VM 独立 reshim）、可写用户层 config（`/data/mise/config.toml`）。共用的只有安装产物与下载缓存。
5. **统一 guest 环境文件**：`/run/sandbox-config/current/guest-env.sh` 由 generator 单一来源生成，`sb sync`（sync-guest.sh）、执行上下文（launcher）、legacy 入口（wrapper entrypoint）统一 source，不再各自维护环境变量块。
6. **宿主写锁**：`sb sync` 在宿主侧经 flock（`~/Data/sandboxes/mise/aarch64-linux/.sync.lock`）串行化，多 VM 并发 sync 不交叉写共用安装层。
7. **sync 只补缺**：只安装缺失的 mise 版本，按清单 `bun install` 补插件；不删除已装工具与插件、不升级、不重建插件依赖，也不清理下载缓存——共用的下载缓存是资产。不区分 VM 忙闲（ADR 0006）。
8. **初始化职责**：主 VM 首次创建后自动 `sb sync` 一次；`sb run`/`sb shell`/`omp-sb` 复用已有 VM 时不自动 sync。
9. **插件在沙箱内完整安装**（修订 ADR 0003 决策 11 的落地方式）：OMP 插件清单按仓库 `modules/features/ai/omp/plugins/package.json` 在 guest 内重放。带 GitHub 有效凭据时，`git+ssh://git@github.com/...` 源被改写为 `https://github.com/...`，凭据由 `GIT_CONFIG_GLOBAL` 的 `insteadOf` 指向占位符 URL（`$MSB_GITHUB_TOKEN`，由 `sb.yaml` 的 `secrets` 声明、msb 在网络边界替换）——token 本身不落盘、不进日志、不进进程参数。
10. **私有插件能装就装**：VM 本地 `.git-vendor` 已有同一依赖且 ref 一致时直接复用；否则对该 git 源依赖做一次禁交互的浅 `git clone`（`GIT_TERMINAL_PROMPT=0`，`--depth 1`，带 ref 时 `--branch`），以 `file:` 依赖安装。clone 失败只在 `sb sync` 输出中警告并继续，不区分失败原因，sync 退出码不受影响；`sb status` 不展示插件状态（ADR 0006）。
11. **不执行依赖安装脚本**（`bun install --ignore-scripts`）：`node-pty`（`@plannotator/webtui` 的依赖）在 Linux 无预编译产物，安装脚本回落 `node-gyp rebuild`，需要 C 工具链。实测补齐 gcc-wrapper 的闭包增量 **1.3 GiB**（gcc-wrapper 370 MiB、binutils 121 MiB、isl/mpfr/mpc/gcc 等），远超 200 MiB 预算，故不引入编译器；`node-pty` 仅供 plannotator 的终端桥接，不参与插件加载。若将来确需本地终端桥接，再单独评估工具链预算。

## 后果

- 正面：任何 VM（含 e2e 一次性 VM）首启即有完整工具；下载量从「每 VM 一份」降为「全宿主一份」；sync 幂等，跨 VM 写入串行。
- 负面：共用安装层损坏影响所有 VM（以 `sb sync` 重装自愈）；macOS 端宿主目录体积随工具增长（约 1–2 GB 量级）；无凭据环境下私有插件不可用，只在 `sb sync` 输出中提示；`node-pty` 的原生桥接在沙箱内不可用。

## 词汇

- **共用安装层**（shared install layer）：宿主 `~/Data/sandboxes/mise/aarch64-linux/data`，guest 视角 `/opt/sandbox-mise/data`，存放 mise `installs/` 与 `downloads/`。
