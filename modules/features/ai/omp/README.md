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

`deny_paths` 中带 `-` 前缀的规则声明路径例外，可从通配禁令中放行指定文件。按“内置 → 全局 → 项目”及列表顺序匹配，最后匹配的规则生效：

```yaml
deny_paths:
  - "-compose/demo/.env.tpl"
```

例外适用于读取、写入、两种 `edit` 输入、`ast_edit`、搜索和精确 Git 暂存。相对例外固定到配置加载时的项目目录；它只匹配声明的路径，不能借软链接授权受保护目标。`allow_read_paths` 仍仅授予读取权限。

仓库权限文件通过 `-compose/*/.env.tpl` 显式允许 Compose 模板。内置默认策略保持拒绝模板；真实 `.env`、`.env.production`、`.env.tpl.bak` 和其他目录的模板继续受保护。路径例外不影响 `deny_commands`，全仓暂存禁令继续生效。

拒绝信息中的 `path` / `command` 指明命中规则，`config` 指明规则来源：内置规则标为 `guard.ts#BUILTIN_PATHS` / `guard.ts#BUILTIN_COMMANDS`，用户规则标为实际权限文件路径及配置键。

配置修改后开启新会话生效。
