# omp

- `/export`：在 Web 页面查看完整上下文；`/hub`：查看 subagent 活动状态
- `plugins/install.sh` 将 `plugins/package.json` 拷入运行目录安装，避免写穿仓库工作树
- `models.yml` 的 `apiKey` 填环境变量名：OMP 的 `resolveConfigValue` 先查环境变量，查不到才当字面量

## Guard 权限

同时用于 omp 与 pi（边界与重放见 [extensions/guard/README.md](./extensions/guard/README.md)）。全局权限 `~/.omp/agent/permissions.yaml` 与 `~/.pi/agent/permissions.yaml` 由 `omp/permissions.yaml` 生成；项目权限取 `.omp/permissions.yml` 或 `.pi/permissions.yml`（`.yml` 优先于 `.yaml`），按「内置 → 全局 → 项目」叠加，新会话生效

```yaml
default_reason: "BLOCKED BY USER"
deny_commands:
  - pattern: "git add -A"
    reason: "请显式指定文件"
deny_paths:
  - "-~/.zsh_history"
```
