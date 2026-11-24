# ai

Agent 相关配置，按能力组织（ADR 0008）。`ai` 是跑 agent 的机器都需要的运行时（沙箱设计见 [sandbox/README.md](./sandbox/README.md)）；只在工作站使用的能力作为独立功能加入 `workstation`

## 新增配置放哪

先问执行节点上跑在沙箱里的 agent 用不用得到：用得到放 `ai` 本体；用不到就新建能力目录，自带 skill（登记到 `shelken.dev.ai.skills`）、命令、cask 和沙箱桩（`shelken.dev.sandbox.hostCommands`），并自行加入角色
