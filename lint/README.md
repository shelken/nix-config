# lint

仓库自定义的 lint 规则，用 [ast-grep](https://ast-grep.github.io/) 按语法树匹配，配置入口是根目录的 `sgconfig.yml`

- `rules/`：一条规则一个文件，`message` 写错在哪，`note` 写为什么、该怎么改
- `rule-tests/`：每条规则的正反样例，`valid` 不得命中，`invalid` 必须命中

pre-commit 的 `ast-grep` 钩子扫描提交的文件，`ast-grep-test` 钩子在规则或样例变化时跑样例，定义见 `modules/flake/dev.nix`

只看路径、不看内容的规则不放这里：ast-grep 的样例只有代码片段，测不了路径。这类规则用 pre-commit 的 `language = "fail"` 钩子写在 `modules/flake/dev.nix`，现有 `feature-domains`、`feature-platform-split`（ADR 0012）。要同时看路径、目录内容或维护跨语言棘轮基线的规则写成脚本：

- `feature-layout.py`：用 `ast-grep` 检查无资源单文件目录、入口层级（`<领域>/<名>.nix` 或 `<领域>/<名>/default.nix`，禁止 `<领域>/default.nix`）、按平台命名私有片段白名单及其过时棘轮、转发壳、模块名即文件名、功能文件名全局唯一，由同名钩子调用
- `no-comments.py` 与 `no-comments-baseline.json`：单次调用 `ast-grep` 扫描 `.nix`/`.py`/`.sh`/`.ts`/`.lua` 注释，按文件行数棘轮只减不增；提交时由 `--tighten` 自动收紧基线，只读校验用 `--check`。无法改变的外部约束注释以 `EXTERNAL: <原因>` 开头豁免（多行逐行标注，或用块注释）；`#!`、`#compdef`、`# renovate:` 单行豁免

## 新增规则

1. 用 `--debug-query=cst` 查节点类型
   ```bash
   ast-grep run --lang nix -p '<代码片段>' --debug-query=cst <文件>
   ```
2. 在 `rules/` 写规则，在 `rule-tests/` 写正反样例
3. 跑样例并确认全仓没有误报
   ```bash
   ast-grep test --skip-snapshot-tests
   ast-grep scan
   ```
