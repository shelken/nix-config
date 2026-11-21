# 共享工具单一声明

日期: 2026-10-22

宿主与 Agent 沙箱都要同一批开发工具，原先两边各写一份清单，新增工具要改两处；沙箱还靠独立的 `llm-agents` input 提供 OMP，升级连带约 1.1 GiB 的 Linux 闭包下载。现在 `shelken.dev.tools.<名字>` 只登记两端都需要的共享工具，沙箱侧机制见 [沙箱 README](../../modules/features/ai/sandbox/README.md)

## 规则

- `shelken.dev.tools` MUST 只登记宿主与沙箱都需要的工具，宿主独有工具 MUST NOT 登记
- 同一工具在两端 MUST 使用同一种安装方式
- 安装方式默认走 Nix；CLI 需要较新版本、nixpkgs 跟不上且 mise 管理更方便时 MAY 走 mise，由人工判断
- 沙箱基础环境（bash、coreutils、curl、git、mise 等）MUST NOT 登记为共享工具，避免宿主上的 macOS 自带命令被覆盖

## 考虑过的替代方案

- 统一登记表带 `scope` 字段：要迁约 150 条现有声明，宿主独有工具不需要被沙箱感知
- 从宿主 `home.packages` 按名字推导：实测 `ctx7`、`lit` 匹配到同名无关包，`deepwiki`、`sec-run` 匹配不到
- 保留 `llm-agents`：多维护一份 nixpkgs pin，升级 OMP 仍触发大闭包下载

## 后果

- 登记 mise 的工具宿主 MUST 执行 `mise install`，原由 Nix 安装的同名工具随迁
- `nixfmt`、`deadnix`、`statix` 无 mise 来源，MUST NOT 进沙箱
- 沙箱 Linux Nix 包 MUST 取自本仓库 `nixpkgs`，`llm-agents` input 已删除
- 配置文件随工具登记，沙箱不再按路径前缀过滤
