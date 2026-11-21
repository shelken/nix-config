## 常用指令

- `/export`：在 Web 页面查看完整上下文信息
- `/hub`：查看 subagent 活动状态，深入分析子代理运行上下文

## 插件清单

`plugins/package.json` 以普通文件副本部署而非软链：`omp plugin install` 会原地改写清单，软链会直接写穿到仓库工作树。

## 部署接线

- 扩展：单文件扩展逐个软链，目录扩展整体软链。omp 只加载目录内的 `index.ts`，目录里的测试与文档不会被当成扩展
- `models.yml` 的 `apiKey` 填环境变量名：OMP 的 resolveConfigValue 先查环境变量，查不到才当字面量

## Guard 权限

guard 同时用于 omp 与 pi。拦截范围、内置规则与实现结构见 `extensions/guard/README.md`

权限文件：全局 `~/.omp/agent/permissions.yaml`（omp）与 `~/.pi/agent/permissions.yaml`（pi），都由 `omp/permissions.yaml` 生成；项目 `.omp/permissions.yml`（omp）或 `.pi/permissions.yml`（pi），也支持 `.yaml`，`.yml` 优先。规则按「内置 → 全局 → 项目」叠加，修改后开启新会话生效

- `-值` 只在全局权限文件里生效，只删除同名**路径规则**与**用户命令规则**（路径规则含内置的 `.env`、`~/.ssh/*` 等条目）
- 项目权限文件随仓库克隆而来，只能追加规则：`-值` 会被忽略并提示，同名规则不会替换已有规则，而是另外追加一条
- 权限文件里不能有以 `---` 开头的行（宿主借 frontmatter 解析器读取 YAML，这种行会截断内容）
- 内置命令检查（`rm` 全量删除、下载执行、环境变量全量导出、裸设备）由代码实现，权限文件既不能关闭也不能改写理由
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
