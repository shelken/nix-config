# lint

自定义语法树 lint 规则使用 [ast-grep](https://ast-grep.github.io/)，配置入口为 `sgconfig.yml`，由 `.pre-commit-config.yaml` 触发

- `rules/` 与 `rule-tests/`：按语法树匹配的规则与正反样例（`valid` 不得命中，`invalid` 必须命中）
- `feature-layout.py`：路径与目录布局检查，配合 `.pre-commit-config.yaml` 的 `feature-domains`、`feature-platform-split` 钩子执行（ADR 0012）
- `no-comments.py` 与 `no-comments-baseline.json`：跨语言注释行数棘轮检查；无法改变的外部约束以 `EXTERNAL: <原因>` 开头豁免

## 新增规则

1. 查节点类型：`ast-grep run --lang nix -p '<代码片段>' --debug-query=cst <文件>`
2. 在 `rules/` 写规则，在 `rule-tests/` 写正反样例
3. 校验：`ast-grep test --skip-snapshot-tests && ast-grep scan`
