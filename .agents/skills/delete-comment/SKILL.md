---
name: delete-comment
description: 审计并清理 nix-config 代码注释、把决策记录迁入 ADR/README、收紧 lint/no-comments-baseline.json 棘轮基线时使用
---

# delete-comment

使用 `lint/no-comments.py` 逐条清理代码注释并收紧 `lint/no-comments-baseline.json`。扫描语言、排除路径与豁免前缀的唯一真源在 `lint/no-comments.py`，不在此重复。

## 步骤

### 1. 导出目标范围注释

```bash
python3 lint/no-comments.py --dump [路径...]
```

不传路径时扫描全部已跟踪代码文件。完成标准：拿到目标范围内全部非豁免注释块的精确文件路径与行号。

### 2. 逐条归类

阅读每条注释对应的上下文代码，逐一归入下列五类之一，并审视 `lint` / `formatter` 抑制指令（如 `# shellcheck`、`# noqa`、`# fmt: skip`、`@ts-`）是否真正必要：

- **同义反复（Tautology）**：复述代码本身已表达的逻辑、选项文档或魔法数字
- **过时（Stale）**：记录旧实现、历史变更日记（如 `变更原因:`）或已不成立的说明
- **借口（Excuse）**：为临时绕行或权宜实现辩解
- **决策记录（Decision Record）**：记录难以逆转且非显而易见的设计权衡
- **外部约束（External Constraint）**：记录无法改变的上游缺陷、硬件/系统行为或外部工具协议

完成标准：目标范围内每条非豁免注释块均有明确分类与处理结论。

### 3. 按类处置

- **同义反复 / 过时**：删除注释。遇到魔法数字时，改为具名常量或自解释符号后再删。
- **借口**：删除注释。若根因在当前范围内且改动小，直接修复；否则记录到待确认的 GitHub Issue 清单（本仓库公开，创建 Issue 前必须经用户确认，已有追踪 Issue 不重复创建）。
- **决策记录**：先查 `docs/adr/` 与对应目录 `README.md` 是否已有记录。已有则直接删除注释；未记录时，Nix/仓库/dotconfig 级架构决策写入 `docs/adr/`（遵循既有编号与日期格式），单个软件或脚本设计写入所属目录 `README.md`，随后删除代码注释。
- **外部约束**：确认无法用代码、类型或断言表达。保留为显式豁免时，在注释开头加上 `EXTERNAL: <原因>`（不可留空；多行逐行标注，或用块注释 `/* EXTERNAL: ... */`，不依赖向下继承）；暂不调整的留在基线中待后续轮次消化。

### 4. 收紧棘轮与验证

```bash
python3 lint/no-comments.py --tighten
python3 lint/no-comments.py --check
```

`--tighten` 拒绝任何文件行数上升并在注释减少时自动收紧基线，`--check` 为只读校验（行数上升或基线未收紧均失败）。新增或删除文件后先 `git add` 再执行 Nix 校验。

按受影响范围运行最小验证：

- 修改 `.nix`：对修改文件跑 `nix-instantiate --parse`（或对应 `nix eval`），执行 `just check-ifd` 并确认输出 `0 台跳过`（注意 `check_ifd.py` 遇到非 IFD 求值错误会跳过主机且仍退出 0），以及 `python3 lint/feature-layout.py`、`ast-grep scan`
- 修改 `.ts`：对应 `bun test`
- 修改 `.py`：对应 `python3 -m unittest` 与 `python3 -m py_compile`
- 修改 `.sh` / `.zsh`：`bash -n` 或 `zsh -n`

完成标准：`python3 lint/no-comments.py --check` 退出码为 0，且全部受影响检查通过。

### 5. 输出报告

汇报内容包含：

- 本轮删除注释行数与文件数、基线变化（旧总数 -> 新总数）
- 新增或更新的 ADR / README 路径
- 待用户确认创建的借口类 GitHub Issue 清单（含文件位置、问题描述与是否已有上游/本仓关联 Issue）
- 验证命令与实测结果
