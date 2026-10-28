---
name: pstack-harness
description: pstack 技能在 omp 与 pi 上的宿主映射表。上游 pstack 用 Cursor 的工具名与路径写就，本仓库原样引入并在这里给出等价物。读 pstack 技能前先读本目录下与宿主对应的文件。
---

# pstack harness

上游 pstack 的 `SKILL.md` 保持原样，里面写的 `Task`、`AskQuestion`、`~/.cursor/rules/pstack-models.mdc` 在 omp 与 pi 上都不存在。映射表在这里：

- omp → `omp.md`
- pi → `pi.md`

## 用法

读任一 pstack 技能后，若该技能带有 `This skill uses Cursor names` 开头的指针行，先读本目录下对应宿主的映射表，再按它翻译技能里的 Cursor 名字。没有指针行的技能不含 Cursor 专名，直接执行。

映射表各自的权威范围：

- 工具名、子代理字段、模型角色、路径、仅 Cursor 有的功能，各有一张表。
- 某字段在表里没有对应行时，丢弃它并在回复里说明，不要猜一个等价物。
- 工具 schema 拒绝某个字段或值时，按表里的说明处理，不要换着拼写重试。

