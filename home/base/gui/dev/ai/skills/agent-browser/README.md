# 上游来源

取自 [kasuboski/pi-extensions](https://github.com/kasuboski/pi-extensions) 的 `skills/agent-browser`，对应上游提交 [`e9e0213`](https://github.com/kasuboski/pi-extensions/commit/e9e02134361ea6657a080a8d3b035b68b9dc8525)（2026-04-17）

## 与上游的差异

- `SKILL.md` 从 694 行压缩到 212 行，只保留核心工作流，低频章节原文移入 `references/`
  - 开头新增「先用 `command -v agent-browser` 检查是否已安装，再决定是否安装」的要求
  - 「Handling Authentication」整节改为一段指针，指向 `references/authentication.md` 的「Choosing an Approach」，保留明文 token 的警告
  - 「Batch Execution」「Common Patterns」「Diffing (Verifying Changes)」「Timeouts and Slow Pages」「Annotated Screenshots (Vision Mode)」「Semantic Locators (Alternative to Refs)」「JavaScript Evaluation (eval)」移入 `references/patterns.md`
  - 「Security」「Configuration File」「Browser Engine Selection」移入 `references/configuration.md`
  - 「Deep-Dive Documentation」表新增 `patterns.md`、`configuration.md` 两行
- `references/authentication.md` 新增「Choosing an Approach」一节，内容为原 `SKILL.md` 中认证五种做法的选型说明
- 新增 `references/patterns.md`、`references/configuration.md`，章节内容自上游 `SKILL.md` 原文搬入
- 其余 9 个文件与上游一致，包括 `references/` 下的 `commands.md`、`profiling.md`、`proxy-support.md`、`session-management.md`、`snapshot-refs.md`、`video-recording.md`，以及 `templates/` 下的 3 个脚本
