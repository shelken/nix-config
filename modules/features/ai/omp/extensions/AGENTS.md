# omp-extensions

pi 与 omp 共用的 Agent 扩展目录（omp 自动加载全部条目，pi 按 `modules/features/ai/pi/default.nix` 逐条登记；目录扩展仅加载 `index.ts`）

## 约束

- **禁止执行任何危险的 rm 测试**：验证拦截一律使用纯内存函数 `evaluateGuard` 与 `guard/guard.test.ts` 单元测试，绝不对真实或 `/tmp` 环境运行 `rm -rf` 等破坏性命令
