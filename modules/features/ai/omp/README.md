## 常用指令

- `/export`：在 Web 页面查看完整上下文信息
- `/hub`：查看 subagent 活动状态，深入分析子代理运行上下文

## Guard 权限

权限文件：全局 `~/.omp/agent/permissions.yml`，当前项目 `.omp/permissions.yml`。也支持 `.yaml`；同目录同时存在时优先使用 `.yml`。

```yaml
allow_read_paths:
  - path: "~/.ssh/config"
```

`allow_read_paths` 仅授予读取权限。

`deny_paths` 使用有序 glob：普通模式拒绝匹配路径，`!pattern` 取消之前匹配的拒绝，最后匹配的规则生效。`-pattern` 保留删除同名规则的原有语义。

```yaml
deny_paths:
  - "!compose/demo/.env.tpl"
```

否定模式适用于读取、写入、两种 `edit` 输入、`ast_edit`、搜索和精确 Git 暂存。相对否定模式固定到配置加载时的项目目录，不跟随规则自身的软链接，也不能借链接授权受保护目标。

仓库权限文件通过 `!compose/*/.env.tpl` 声明 Compose 模板范围；匹配代码不识别模板文件名。内置默认仍拒绝模板，真实 `.env`、`.env.production`、`.env.tpl.bak` 和其他目录的模板继续受保护。项目层可添加拒绝规则，或用 `-!compose/*/.env.tpl` 删除全局否定规则。

`deny_commands` 的删除语义和 `allow_read_paths` 的只读语义保持原样，路径否定模式不影响全仓暂存禁令。

拒绝信息中的 `path` / `command` 指明命中规则，`config` 指明规则来源：内置规则标为 `guard.ts#BUILTIN_PATHS` / `guard.ts#BUILTIN_COMMANDS`，用户规则标为实际权限文件路径及配置键。

配置修改后开启新会话生效。
