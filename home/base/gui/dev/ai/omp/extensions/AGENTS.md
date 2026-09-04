# omp-extensions

OMP Agent 扩展目录（guard.ts 安全防护扩展等），经 Home Manager 部署至 `~/.omp/agent/extensions/`。

## 约束

- **禁止执行任何危险的 rm 测试**：验证拦截一律使用纯内存函数 `evaluateGuard` 与 `guard.test.ts` 单元测试，绝不对真实或 `/tmp` 环境运行 `rm -rf` 等破坏性命令
