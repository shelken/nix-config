# 上游来源

取自 [OctavianTocan/agy-review](https://github.com/OctavianTocan/agy-review) 仓库根目录的 `SKILL.md` 和 `scripts/`，对应上游提交 [`ed4a4f4`](https://github.com/OctavianTocan/agy-review/commit/ed4a4f4d9387424ee059ebe3f008dd57d12d8533)（2026-06-07）

上游许可 MIT（Copyright (c) 2026 Octavian Tocan）

## 与上游的差异

- `SKILL.md` 的 frontmatter 删去 `user-invocable`、`argument-hint`、`stages`，新增 `disable-model-invocation: true`
- 默认模型由 `Gemini 3.5 Flash (High)` 改为 `gemini-3.6-flash-high`，`SKILL.md` 和 `scripts/agy-review.sh` 同步修改，后者涉及文件头注释、用法说明和 `MODEL` 默认值
- 上游的 `.gitignore`、`CHANGELOG.md`、`LICENSE`、`README.md` 未带入
