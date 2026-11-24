# guard

pi 与 omp 共用的工具调用拦截扩展。权限文件的写法见 `modules/features/ai/omp/README.md`「Guard 权限」

## 定位

- 拦截配合的 agent 手滑：误删大范围目录、误读凭据、执行未落盘的下载脚本
- 不防对抗性绕过：`bun -e 'readFileSync(".env")'` 这类解释器内读取不在范围内，隔离交给 sb 沙箱
- 误伤按缺陷处理：拦截只落在真实危险目标上，规则变更用会话重放衡量误伤
- 内置规则只放通用安全项；个人操作规范（全仓暂存、硬 reset、全盘 `find`）写在全局权限文件，拒绝理由给出替代做法

## 误伤重放

```bash
bun modules/features/ai/omp/extensions/guard/replay.ts modules/features/ai/omp/extensions/guard/guard.ts
OMP_AGENT_DIR=/tmp/agent-new bun modules/features/ai/omp/extensions/guard/replay.ts modules/features/ai/omp/extensions/guard/guard.ts --samples "rm -rf *"
```
