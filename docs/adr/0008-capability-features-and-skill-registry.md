# ai 按能力拆成独立功能，skill 随功能登记

日期: 2026-11-14

`ai` 原先按实现机制分文件：CLI 汇总在 `cli.nix`，沙箱桩汇总在 `host-commands/`，skill 汇总在 `skills/`，cask 汇总在 `darwin.nix`，一个能力分散三四处，整个 `ai` 只能被整体导入。现在把只在部分机器需要的能力拆成独立功能，各自一个目录，装着这个能力的 skill、命令、cask 与沙箱桩；`ai` 只保留跑 agent 的机器都需要的运行时

## 规则

- 能力判据：执行节点上跑在沙箱里的 agent 是否用得到。用不到的 MUST 拆成独立功能并按 ADR 0004 自行声明角色，用得到的 MUST 留在 `ai`
- 功能自带的 skill MUST 放在功能目录下、目录名即 skill 名，MUST 登记到 `shelken.dev.ai.skills`；该选项声明在 core，部署实现在 `modules/features/ai/skill.nix`
- `skills/` MUST 只放所有导入 `ai` 的机器都需要的 skill
- 「命令只能在宿主执行」MUST 由命令所属的功能写 `shelken.dev.sandbox.hostCommands`，MUST NOT 集中在 `host-commands/`

## 考虑过的替代方案

- 拆成 `ai` 与 `ai-desk` 两个桶：桶内仍按机制分文件，只是换个更小的大杂烩
- skill 留在 `skills/`、功能目录只放 nix：所有导入 `ai` 的机器都部署工作站专属 skill，agent 读到 skill 却找不到命令
- 给 `ai` 各项加 `enable` 开关：ADR 0004 已放弃开关组合

## 后果

- skill 不再只在一个目录，查找本地 skill MUST 同时看 `skills/` 与 `shelken.dev.ai.skills` 的登记
- 登记的 skill 与 `skills/`、外部 skill 重名时求值失败
- 登记的 skill 只在导入 `ai` 的主机上部署，只导入功能而不导入 `ai` 的主机上登记不生效
