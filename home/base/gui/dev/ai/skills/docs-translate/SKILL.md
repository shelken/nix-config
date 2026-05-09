---
name: doc-translate
description:
  Translate documents in place while preserving original copy. Use when user provides document
  path/name and asks to translate, convert language, localize, or says translate document without
  specifying full workflow.
---

# Doc Translate

## 触发

用户传入文档路径或文档名，要求翻译/转换语言/本地化文档。

## 默认行为

- 目标语言：优先按用户要求；未指定时转为英文。
- 原文备份：翻译前将原文件复制为 `[原名]_[原语言代码].[扩展名]`。
- 相同语言：目标语言与原语言一致时，提示无需转换并停止。
- 输出位置：直接把原路径文件内容替换为目标语言版本。
- 保留结构：尽量保留标题层级、列表、表格、代码块、链接、Front Matter、占位符、变量名。
- 不翻译内容：代码、命令、路径、URL、配置键、API 名、品牌/产品专名，除非用户明确要求。

## 工作流

1. 定位文档
   - 用户给路径：直接使用。
   - 用户给名字：在当前仓库搜索同名或近似匹配文件；多结果时询问选择。

2. 读取内容
   - 文本文件用 `read`。
   - PDF/DOCX/PPTX/XLSX/图片等非纯文本，先使用 `liteparse` 技能抽取内容。

3. 判断语言
   - 根据正文主要语言判断原语言。
   - 若目标语言与原语言一致，提示无需转换并停止。
   - 备份语言代码匹配原文件名大小写：原名全部大写时用 `CN`、`EN`、`JP`；其他情况用
     `cn`、`en`、`jp`。
   - 例：`README.md` 中文原文 → `README_CN.md`；`guide.md` 中文原文 → `guide_cn.md`。

4. 备份原文件
   - 复制原文档到 `[原名]_[原语言代码].[扩展名]`。
   - 若备份已存在，停止并询问，避免覆盖用户数据。

5. 翻译并写回
   - 按目标语言翻译全文。
   - 保持原格式和语义，不新增解释、不删减内容。
   - 用 `write` 或 `edit` 覆盖原文件。

6. 验证
   - 重新读取原文件和备份文件，确认二者存在。
   - 对 Markdown/Nix/JSON/YAML 等可校验格式，运行对应格式/语法检查；无检查器时至少确认文件非空且结构保留。

## 翻译规则

- 忠实优先，润色次之。
- 标题短句可自然化，但不得改变含义。
- 技术文档术语前后一致。
- 保留 Markdown 链接目标，只翻译链接文本。
- 保留代码块原样；代码块外行内代码也原样保留。
- Front Matter 只翻译可见文案字段，保留键名和结构。

## 文件命名示例

- `GUIDE.md` 中文转英文：备份 `GUIDE_CN.md`，`GUIDE.md` 写入英文。
- `guide.md` 中文转英文：备份 `guide_cn.md`，`guide.md` 写入英文。
- `docs/spec.yaml` 英文转日文：备份 `docs/spec_en.yaml`，`docs/spec.yaml` 写入日文。

## 失败处理

- 找不到文档：说明搜索范围和匹配结果，询问准确路径。
- 多个候选：列出路径，等待用户选择。
- 备份名冲突：停止，不覆盖。
- 二进制格式无法安全写回：先说明限制，建议输出为 Markdown 或让用户确认目标格式。
