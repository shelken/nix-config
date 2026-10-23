# 上游来源

改编自 [cursor/plugins](https://github.com/cursor/plugins) 的 `pstack/skills/interrogate`，导入时的上游提交推定为 [`63d938c`](https://github.com/cursor/plugins/commit/63d938c2e4a165a0fec1bd0f61a8e325f0cb751e)（2026-08-13）

推定依据是 4 个未改动的 `references/` 文件与该提交一致，但 `d45ad02`（2026-07-25）和 `04166ac`（2026-07-23）的这些文件哈希相同，无法区分。导入时 `SKILL.md` 已是中文改编，不能逐行比对，因此取导入前最近的一次上游提交

## 与上游的差异

- `SKILL.md` 译为中文，派发方式由 Cursor 的 `Task` 工具改为 `spawn-subagent` 加 pi-intercom，见 `../subagent-policy/SKILL.md`
- reviewer 清单不再读上游的 `~/.cursor/rules/pstack-models.mdc`，改为用 `spawn-subagent list` 取名为 `reviewer-<变体>` 的 profile，profile 由 nix 按 omp 的 `modelRoles` 生成
- `references/code-quality-review.md`、`references/lead-judgment.md`、`references/rubric.md` 各有 2 到 4 行措辞改动
- `references/reviewer-prompt.md` 与上游一致
- 上游 pstack 的同名技能在 `../../skill.nix` 的 `pstack.exclude` 中排除，避免冲突
