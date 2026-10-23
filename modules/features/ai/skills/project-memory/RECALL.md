# Recall 参考

本文件为 `recall` 模式的完整流程与输出格式。共用规则（调用约定、冲突裁决、安全边界）见 `SKILL.md`。

回答时优先引用当前代码、Git、测试、运行结果或正式文档。Session 用于定位和补足这些来源未覆盖的历史信息；默认转述，只有用户明确要求原文或措辞本身影响结论时才直接引用。

## 当前 Session

只使用当前 Agent 可见上下文，不声称拥有完整当前 Session 历史。

## 跨 Session

1. 把用户问题展开为少量可验证查询词（错误文本、文件路径、函数名、模块名、领域术语、commit、Issue/PR 标识）
2. 默认只搜当前项目；只有用户明确要求才跨项目或含废弃分支：

```sh
bun run --cwd "$PM_DIR" pm -- search "<query>"
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-projects
bun run --cwd "$PM_DIR" pm -- search "<query>" --all-branches
```

3. 用 `show` 安全展开候选上下文（默认脱敏限长，`--no-redact` 出原文，程序消费加 `--format json`）：

```sh
bun run --cwd "$PM_DIR" pm -- show "<session-id>:<entry-id>" --context 5 --max-chars 8000
```

已知目标会话时用选择器避免全项目正文搜索：`show --session previous --entry last-user`、`search "<query>" --session previous`（`--session` 接受完整 ID/唯一前缀/`latest`/`previous`；`--entry` 接受完整 ID/`last`/`last-user`/`last-assistant`）。还原完整因果链用 `show --session previous --transcript`（默认只读 active lineage，`--all-branches` 含废弃分支）。跨项目或废弃分支结果必须重复对应作用域参数。

4. Compaction 和 branch summary 只用于召回与初筛；正式结论必须回到原始 Entry
5. 找到历史结论后，用当前代码、Git、测试或运行结果重新验证再回答

废弃分支命中必须标记为 abandoned，并按失败尝试或反向证据处理。

涉及模型纠错/复读时，降智嫌疑判定见 [MINE.md](MINE.md) 分析纪律 #4（不写 rule，只计数）。

## 输出格式

```text
查询范围：
历史命中：
当前验证：
冲突与失效信息：
结论：
```
