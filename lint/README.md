# lint

仓库自定义的 lint 规则，用 [ast-grep](https://ast-grep.github.io/) 按语法树匹配，配置入口是根目录的 `sgconfig.yml`

- `rules/`：一条规则一个文件，`message` 写错在哪，`note` 写为什么、该怎么改
- `rule-tests/`：每条规则的正反样例，`valid` 不得命中，`invalid` 必须命中

pre-commit 的 `ast-grep` 钩子扫描提交的文件，`ast-grep-test` 钩子在规则或样例变化时跑样例，定义见 `modules/flake/dev.nix`

只看路径、不看内容的规则不放这里：ast-grep 的样例只有代码片段，测不了路径。这类规则用 pre-commit 的 `language = "fail"` 钩子写在 `modules/flake/dev.nix`，现有 `feature-domains`、`feature-platform-split`（ADR 0012）。要同时看路径与目录内容的规则写成脚本，现有 `feature-layout.py`（无资源单文件目录、转发壳、模块名即文件名），由同名钩子调用

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
