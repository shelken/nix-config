# 共享工具单一声明

日期 2026-10-22

宿主和 Agent 沙箱都需要同一批开发工具。旧做法在两边各写一份清单，新增工具要改两处，沙箱还依赖独立的 `llm-agents` input 拉取第二份 nixpkgs 闭包。现在 `shelken.dev.tools` 只声明两端共用的工具，沙箱的 Linux Nix 包取自本仓库 `nixpkgs`，实现见 [沙箱 README](../../modules/features/ai/sandbox/README.md)

## 规则

- `shelken.dev.tools` MUST 只登记宿主与沙箱都需要的工具，宿主独有工具 MUST NOT 登记
- 同一共享工具在两端 MUST 使用同一种安装方式
- 共享工具默认走 Nix。需要较新版本且 mise 管理更方便的 CLI MAY 走 mise，由人工判断
- 沙箱基础环境工具（bash、coreutils、curl、git、mise）MUST NOT 登记为共享工具，防止覆盖宿主 macOS 自带命令

## 考虑过的替代方案

- 全部工具迁入统一登记表并加 `scope` 字段。宿主独有工具数量大且不需要被沙箱感知，迁移收益低
- 从宿主 `home.packages` 按包名推导 Linux 包。实测同名包会错配，自定义命令找不到对应包
- 保留独立的 `llm-agents` input。多维护一份 nixpkgs 锁点，每次升级拉取重复的 Linux 闭包
