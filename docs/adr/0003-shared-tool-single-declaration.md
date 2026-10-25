# 共享工具单一声明

日期: 2026-10-22

宿主和 Agent 沙箱都需要同一批开发工具，原先两边各写一份清单，新增一个工具要改两处，沙箱还靠独立的 `llm-agents` input 提供 OMP，升级时要连带下载约 1.1 GiB 的 Linux 闭包。现在 `shelken.dev.tools.<名字>` 只登记两端都需要的工具，宿主独有的工具保持原写法、不迁移。一个工具在两端使用同一种安装方式：基础工具与运行时（rg、fd、jq、gh、node、python3、uv）走 Nix，其余（omp、pi、codex、claude-code、bun）走 mise，由用户显式安装，不随 nixpkgs 滚动。配置文件随工具登记，沙箱不再按路径前缀过滤。沙箱的 Linux Nix 包取自仓库 `nixpkgs`，`llm-agents` input 已删除。沙箱侧的补齐、授权等机制见 [沙箱 README](../../modules/features/ai/sandbox/README.md)

## 考虑过的替代方案

- **所有工具迁入统一登记表并带 `scope` 字段**：要迁约 150 条现有声明，宿主侧改动大，而宿主独有的工具不需要被沙箱感知
- **从宿主 `home.packages` 按名字推导 Linux 包**：实测不可靠，`ctx7`、`lit` 会匹配到同名但无关的包，`deepwiki`、`sec-run` 匹配不到
- **保留 `llm-agents`**：多维护一份 nixpkgs pin，升级 OMP 仍触发大闭包下载
- **同一工具宿主用 Nix、沙箱用 mise**：同一个工具出现两套升级语义

## 后果

- 登记为 mise 的工具，宿主也要 `mise install`；原本由 Nix 安装的同名工具迁到 mise
- `nixfmt`、`deadnix`、`statix` 没有 mise 来源，只留在宿主 Nix，不进沙箱
- 沙箱基础环境（bash、coreutils、curl、git、mise 等）不登记为共享工具，否则宿主会被 GNU `coreutils`、Nix 版 `bash` 覆盖 macOS 自带的同名命令
- 沙箱的 Nix 部分实测解压后约 642 MiB（基础 CLI）加 309 MiB（运行时），低于原来的约 1.1 GiB
