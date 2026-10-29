## 常用指令

- `/export`：在 Web 页面查看完整上下文信息
- `/hub`：查看 subagent 活动状态，深入分析子代理运行上下文
## Guard 权限

只读豁免写在权限文件中：全局 `~/.omp/agent/permissions.yaml`，当前项目用 `.omp/permissions.yaml`

```yaml
allow_read_paths:
  - path: "~/.ssh/config"
```

配置修改后开启新会话生效；授权仅用于读取
