## Tips

- `/export`: 在web页面查看完整的上下文信息
- `/hub`: 查看subagent活动状态,深入查看子代理的运行上下文

## 安全沙箱 (cco)

已弃用应用层 guard，采用 OS 原生内核沙箱（macOS Seatbelt / Linux bubblewrap）：

- `somp`: 以内核沙箱安全模式启动 OMP（`sec-run cco --safe omp`）
- **默认最小权限**：仅当前项目目录可读写；家目录（`~/.ssh`, `~/.aws`, 私钥等敏感信息）默认全盘禁止读取；系统全盘禁止写入
- **显式开放**：
  - 显式只读路径：`cco --allow-readonly <path> omp`
  - 显式读写路径：`cco --add-dir <path>:rw omp`
