## 常用指令

- `/export`：在 Web 页面查看完整上下文信息
- `/hub`：查看 subagent 活动状态，深入分析子代理运行上下文

## Guard 权限

拦截范围、内置规则与实现结构见 `extensions/guard/README.md`

权限文件：全局 `~/.omp/agent/permissions.yml`，项目 `.omp/permissions.yml`，也支持 `.yaml`。规则按「内置 → 全局 → 项目」叠加，`-值` 删除同名规则。修改后开启新会话生效

- 命令规则按词前缀匹配：`git add -A` 只命中这一步命令，`git add -- 文件` 照旧执行
- 路径规则只有拒绝语义，没有放行语法；要收紧内置例外，追加更窄的拒绝规则即可

```yaml
default_reason: "BLOCKED BY USER"
deny_commands:
  - pattern: "git add -A"
    reason: "请显式指定文件"
deny_paths:
  - path: "~/.specific.zsh"
    reason: "personal shell secrets"
  - "-~/.zsh_history"
```

拒绝信息给出命中规则（`command:` / `path:`）与来源（`config:`）：内置规则标为 `guard#BUILTIN_*`，用户规则标为权限文件路径及配置键
