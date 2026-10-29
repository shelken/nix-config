## 常用指令

- `/export`：在 Web 页面查看完整上下文信息
- `/hub`：查看 subagent 活动状态，深入分析子代理运行上下文

## Guard 权限

权限文件：全局 `~/.omp/agent/permissions.yaml`，当前项目 `.omp/permissions.yaml`。也支持 `.yml`；同目录同时存在时优先使用 `.yaml`。

```yaml
allow_read_paths:
  - path: "~/.ssh/config"
```

`allow_read_paths` 仅授予读取权限。

需要读取、修改和显式暂存环境模板时，添加精确模板路径：

```yaml
allow_template_paths:
  - path: "compose/demo/.env.tpl"
```

仅对已确认不含真实凭据的模板添加授权。路径必须指向单个 `.env.tpl` 文件，不支持通配符或目录；相对路径固定到加载配置时的项目目录。可用 `- "-compose/demo/.env.tpl"` 在项目层撤回全局授权。

授权覆盖 `read`、`write`、两种 `edit` 输入、`ast_edit`、`grep`、`glob` 和 Bash 中的精确路径操作，例如 `git add -- compose/demo/.env.tpl`。它仅豁免内置环境文件规则；自定义 `deny_paths` 仍可拒绝模板，软链接不能借此访问受保护文件。真实 `.env`、`.env.production` 和未授权模板继续受保护；配置中的全仓暂存禁令继续生效。

拒绝信息中的 `path` / `command` 指明命中规则，`config` 指明规则来源：内置规则标为 `guard.ts#BUILTIN_PATHS` / `guard.ts#BUILTIN_COMMANDS`，用户规则标为实际权限文件路径及配置键。

配置修改后开启新会话生效。
