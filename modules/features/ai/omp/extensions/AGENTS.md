# omp-extensions

OMP Agent 扩展目录（`guard/` 安全防护扩展、subdir-context.ts 子目录上下文自动注入等），经 Home Manager 部署至 `~/.omp/agent/extensions/`。单文件扩展是 `extensions/<名>.ts`；`extensions/guard/` 这类目录扩展只加载目录内的 `index.ts`，其他文件（`shell.ts`、测试、README）不会被当成扩展。

## 约束

- **禁止执行任何危险的 rm 测试**：验证拦截一律使用纯内存函数 `evaluateGuard` 与 `guard/guard.test.ts` 单元测试，绝不对真实或 `/tmp` 环境运行 `rm -rf` 等破坏性命令
