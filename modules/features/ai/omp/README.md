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

`.env.tpl` 按模板处理，内置环境文件规则允许读取、编辑、搜索和显式 Git 暂存，无需额外配置。真实 `.env`、`.env.production` 及 `.env.tpl.bak` 等文件继续受保护。

模板规则仅放行普通文件和待创建文件；目录、软链接、自定义 `deny_paths` 及全仓暂存禁令继续按原策略处理。

拒绝信息中的 `path` / `command` 指明命中规则，`config` 指明规则来源：内置规则标为 `guard.ts#BUILTIN_PATHS` / `guard.ts#BUILTIN_COMMANDS`，用户规则标为实际权限文件路径及配置键。

配置修改后开启新会话生效。
