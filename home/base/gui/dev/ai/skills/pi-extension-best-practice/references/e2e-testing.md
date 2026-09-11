---
name: pi-extension-e2e-testing
description: pi 插件端到端契约测试编写模板与选跑矩阵
---

# 插件契约测试规范

测试目标为验证插件对外能力的可用性及生命周期安全, 防范跨底座兼容回退, 杜绝过度拟合内部实现

## 变更决策与测试矩阵

修改代码时, 按 Git Diff 范式选择测试策略:

| 变更类型 | Diff 范式 | 必跑测试 | 契约测试维护规则 |
| :--- | :--- | :--- | :--- |
| **内部重构 / 内部 Bug** | 仅修改 `src/` 私有实现, 对外能力未变 | 对应单元测试 | 严禁增加特化契约测试, 保持全量契约测试绿灯 |
| **对外功能增改** | 新增或修改 Provider、Command、Tool、Flag | 全量单元测试 | 必须在 `tests/contract.test.ts` 补充标识与格式断言 |
| **生命周期 / 兼容层** | 修改 `index.ts`、增加生命周期钩子（如 `turn_start`） | 全量单元测试 | 在状态机仿真测试中增加对新钩子的兼容断言 |

## 零依赖通用契约测试模板

所有独立仓库或 monorepo 子包的 `tests/contract.test.ts` 均统一采用以下模板:
仅依赖各插件已有的 `vitest` 与 Node.js 内置模块, 无需跨仓库安装共享依赖包

```ts
import { execFileSync } from "node:child_process"
import { describe, expect, it } from "vitest"

describe("Pi Extension Contract Baseline", () => {
  // 1. 真实 CLI 静态加载与零崩溃断言
  it("loads cleanly via official pi CLI without error", () => {
    const stdout = execFileSync("pi", ["--no-extensions", "-e", "./index.ts", "--list-models"], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    })
    expect(stdout.length).toBeGreaterThan(0)
  })

  // 2. 宿主装配与公开契约断言 (按插件实际暴露能力断言)
  it("registers valid capabilities into ExtensionAPI", async () => {
    const providers: string[] = []
    const commands: string[] = []
    const events: Record<string, Function[]> = {}

    const fakePi = {
      registerProvider: (id: string) => providers.push(id),
      registerCommand: (name: string, def: any) => {
        expect(name).not.toMatch(/^\//) // 规范: 命令名禁止带斜杠
        expect(def.handler).toBeTypeOf("function")
        commands.push(name)
      },
      on: (event: string, handler: Function) => {
        ;(events[event] = events[event] || []).push(handler)
      },
    }

    const mod = await import("../index.ts")
    const factory = mod.default || mod
    factory(fakePi)

    // 在此补充当前插件对外承诺的 Provider 或 Command 标识
    // expect(providers).toContain("example-provider")
    // expect(commands).toContain("example-command")
  })

  // 3. 无 UI / 脚本模式容灾与 Prompt 安全演进
  it("survives headless lifecycle state machine", async () => {
    const events: Record<string, Function[]> = {}
    const fakePi = {
      registerProvider: () => {},
      registerCommand: () => {},
      on: (event: string, handler: Function) => {
        ;(events[event] = events[event] || []).push(handler)
      },
    }
    const mod = await import("../index.ts")
    ;(mod.default || mod)(fakePi)

    const headlessCtx = {
      cwd: process.cwd(),
      hasUI: false,
      model: { id: "test/model", provider: "test" },
      ui: { setStatus: () => {}, notify: () => {} },
    }

    // 触发 session_start
    for (const fn of events["session_start"] || []) {
      await expect(Promise.resolve(fn({}, headlessCtx))).resolves.not.toThrow()
    }

    // 触发 before_agent_start
    for (const fn of events["before_agent_start"] || []) {
      const res = await fn({ systemPrompt: "base prompt" }, headlessCtx)
      if (res?.systemPrompt && typeof res.systemPrompt === "string") {
        expect(res.systemPrompt).toContain("base prompt")
      }
    }
  })
})
```

## 统一验证门禁

在插件目录的 `justfile` 中声明标准指令:
交付前必须运行 `just verify`, 确保测试通过

```just
verify:
    tsc --noEmit
    bun test
```
