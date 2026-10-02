## Tips

- `/export`: 在web页面查看完整的上下文信息
- `/hub`: 查看subagent活动状态,深入查看子代理的运行上下文

## Guard 权限

规则由内置默认、全局 `permissions.yaml`、当前项目 `.omp/permissions.yaml` 依次合并，配置修改后开启新会话生效

Guard 是静态风险检测，不替代进程沙箱；下载管道和只读授权使用保守的命令识别。

SSH 配置和 `.env.example`、`.env.tpl` 默认仍受保护，确认文件不含 agent 不应接触的凭据后，在权限文件中逐个授权：

```yaml
allow_read_paths:
  - path: "~/.ssh/config"
    reason: "已确认主机配置可供 agent 只读查询"
  - path: "compose/demo/.env.tpl"
    reason: "已确认模板仅含占位符"
```

- 授权仅接受普通文件的确切路径，不接受目录或通配符；项目文件应在项目权限文件中授权
- 只读授权不允许写入、编辑、重命名或重定向写入；指向其他受保护文件的软链接仍会被拦截
- bash 的文件授权仅支持单条直接 `cat`、`head`、`tail`、`grep`，不放行管道、重定向、动态展开、命令包装或换目录后的间接读取
- 受限元数据查询及字面路径回显不等同于内容读取，但不豁免活跃通配符或向管道下游传递秘密路径；秘密目录枚举及全量环境变量导出仍受保护
- `git add -A` 需指定明确文件或子目录；交互选取和 dry-run 不视为全量写入，机密路径仍受保护
- 本仓库非机密机器选择配置使用 `.host-profile`，迁移步骤见仓库根目录 README
- 下载管道允许 `jq` 等数据处理器；`python -c` 仅放行 `import json,sys` 之后直接 `print(json.load(sys.stdin)` 取字段的固定形态，其他脚本仍拦截

回归检查只在内存中评估危险命令，不执行删除：

```bash
bun test home/base/gui/dev/ai/omp/extensions/guard.test.ts
```
