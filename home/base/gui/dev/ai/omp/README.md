## Tips

- `/export`: 在web页面查看完整的上下文信息
- `/hub`: 查看subagent活动状态,深入查看子代理的运行上下文

## Guard 权限

只读豁免写在权限文件中：全局 `~/.omp/agent/permissions.yaml`，当前项目用 `.omp/permissions.yaml`；家目录凭据（如 `~/.ssh/config`）只能写在全局文件，项目文件随仓库分发、只允许授权项目目录内的路径

```yaml
# ~/.omp/agent/permissions.yaml（全局）
allow_read_paths:
  - path: "~/.ssh/config"
```

配置修改后开启新会话生效；授权仅用于读取
