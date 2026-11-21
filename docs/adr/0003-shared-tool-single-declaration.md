# 共享工具单一声明

日期: 2026-10-22

宿主与 Agent 沙箱都需要同一批开发工具，原先两边各写一份清单，新增工具要改两处，且沙箱靠独立的 `llm-agents` input 拉取另一份 nixpkgs 闭包。现在 `shelken.dev.tools.<名字>` 只登记两端共用的工具，沙箱的 Linux Nix 包取自本仓库 `nixpkgs`，实现细节见 [沙箱 README](../../modules/features/ai/sandbox/README.md)

## 规则

- `shelken.dev.tools` MUST 只登记宿主与沙箱都需要的工具，宿主独有工具 MUST NOT 登记
- 同一工具在两端 MUST 使用同一种安装方式
- 安装方式默认走 Nix；需要较新版本且 mise 管理更方便的 CLI MAY 走 mise，由人工判断
- 沙箱基础环境（bash、coreutils、curl、git、mise 等）MUST NOT 登记为共享工具，避免覆盖宿主的 macOS 自带命令

## 考虑过的替代方案

- 统一登记表带 `scope` 字段：要迁大量宿主独有声明，沙箱不需要感知它们
- 从宿主 `home.packages` 按名字推导：实测同名包会错配或找不到
- 保留 `llm-agents`：多维护一份 nixpkgs pin，升级触发重复的大闭包下载
