# skill 单一入口 shelken.dev.ai.skills

日期 2026-11-15

skill 原先分散在目录自动扫描、外部 skill 中心清单和功能登记三个入口，外部 skill 无法随具体功能按需部署。现在全仓收敛到 `shelken.dev.ai.skills` 唯一入口，由各功能自行声明，实现与声明格式见 `modules/features/ai/skill.nix` 与 `modules/features/ai/skills/README.md`

## 规则

- 所有 skill 声明 MUST 写在 Home Manager 模块的 `shelken.dev.ai.skills` 列表中，谁需要就由谁声明
- 部署形态 MUST 平铺，MUST NOT 按来源分组
- 同一主机上出现重名 skill 时求值 MUST 失败
- CI 追踪外部 skill 上游变更 MUST 从主机求值结果 `flake.skillUpstreams` 获取，MUST NOT 维护平行中心清单。CI MAY 跳过因私有输入求值失败的主机，跳过时 MUST 输出告警

## 考虑过的替代方案

- 把 skill 声明移到 flake-parts 层。CI 不必求值主机，但所有功能模块都要改写接口
- 不经主机合并全部 HM 模块求值。模块脱离真实主机上下文会因缺少系统选项与参数而求值失败
- 保留分组部署形态。分组名来自已删除的中心清单，没有任何目标在使用
