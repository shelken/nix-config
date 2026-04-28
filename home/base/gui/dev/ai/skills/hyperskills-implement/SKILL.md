---
name: hyperskills-implement
description:
  Use this skill when writing code — building features, fixing bugs, refactoring, or any multi-step
  implementation work. Activates on mentions of implement, build this, code this, start coding, fix
  this bug, refactor, make changes, develop this feature, implementation plan, coding task, write
  the code, or start building.
---

# Implementation

**核心洞察：**
每 2-3 次编辑后验证一次。73% 的修复缺少验证——这是首要质量缺口。干净会话和调试螺旋的差异，往往来自验证节奏。

## The Sequence

无论规模大小，每次实现都遵循同一套宏观序列：

```dot
digraph implement {
    rankdir=LR;
    node [shape=box];

    "ORIENT" [style=filled, fillcolor="#e8e8ff"];
    "PLAN" [style=filled, fillcolor="#fff8e0"];
    "IMPLEMENT" [style=filled, fillcolor="#ffe8e8"];
    "VERIFY" [style=filled, fillcolor="#e8ffe8"];
    "COMMIT" [style=filled, fillcolor="#e8e8ff"];

    "ORIENT" -> "PLAN";
    "PLAN" -> "IMPLEMENT";
    "IMPLEMENT" -> "VERIFY";
    "VERIFY" -> "IMPLEMENT" [label="fix", style=dashed];
    "VERIFY" -> "COMMIT" [label="pass"];
    "COMMIT" -> "IMPLEMENT" [label="next chunk", style=dashed];
}
```

**ORIENT（了解上下文）** — 修改前先阅读现有代码。`Grep -> Read -> Read`
是最常见的开场方式。第一次编辑前阅读 10+ 个文件的会话，后续修复迭代通常更少。避免盲目修改。

**PLAN（计划）**
— 按规模决定（见下文）。琐碎修复可以跳过；功能开发需要任务列表；史诗级任务需要研究集群。

**IMPLEMENT（实现）**
— 每批完成 2-3 次编辑，然后验证。遵循依赖链。优先编辑现有文件，和新建文件的比例约为 9:1。错误出现后立即处理，避免累积。

**VERIFY（验证）**
— 类型检查是主要关卡。每 2-3 次编辑后运行一次。功能完成后运行测试。提交前运行完整测试套件。

**COMMIT（提交）**
— 以原子块提交，边做边提交。验证、暂存指定文件、提交，然后进入下一个块。每个会话通常包含多次小提交。消息结构见下文**提交节奏**。

---

## Code Discipline

贯穿循环每个阶段的行为准则。改编自 Karpathy 对 LLM 编码陷阱的[观察](https://x.com/karpathy/status/2015883857489522876)——模型"替你做出错误假设，然后一路执行而缺少检查……它们很容易把代码和 API 过度复杂化，制造膨胀的抽象……明明 100 行足够，却写出 1000 行的臃肿结构。"

这些原则更偏向谨慎，速度放在其后。琐碎修复按实际情况判断。

### Think before coding

不要假设。不要隐藏困惑。主动说明权衡。

| 情况                 | 行动                     |
| -------------------- | ------------------------ |
| 请求有多种解释       | 呈现它们；不要默默选择   |
| 更简单的方法可行     | 说出来；必要时提出异议   |
| 某些东西不清楚       | 停下；说明困惑之处；询问 |
| 你持有关键假设       | 明确说明                 |
| 请求与代码之间不一致 | 继续前说明               |

ORIENT（阅读代码）是前提。这个原则关注如何处理阅读后的发现：说清楚缺口，别掩盖。

### Simplicity first

用尽量少的代码解决问题。不做推测性设计。

| 不要                                | 要                         |
| ----------------------------------- | -------------------------- |
| 添加超出要求的功能                  | 准确解决陈述的问题         |
| 为单次使用的代码构建抽象            | 先内联；重用时再抽象       |
| 添加未被要求的"灵活性"或可配置性    | 当前先固定；需要时再参数化 |
| 处理不可能场景的错误                | 信任内部不变量；在边界验证 |
| 用 200 行写本可以用 50 行完成的代码 | 重写得更紧凑               |

判断标准：资深工程师会觉得它过度复杂吗？会的话就简化。

### Surgical changes

只改必须改的地方。只清理自己造成的问题。

| 规则                                   | 为什么                         |
| -------------------------------------- | ------------------------------ |
| 不要"改进"相邻代码、注释或格式         | 污染 diff；超出本次范围        |
| 不要重构当前无关的代码                 | 范围蔓延会扩大影响面           |
| 即使你会以不同方式做，也要匹配现有风格 | 局部一致性胜过你的偏好         |
| 注意到无关的死代码 → 提及，不要删除    | 其他分支/代理可能依赖它        |
| 删除被你的更改遗留的导入/变量/函数     | 自己造成的问题自己清理         |
| 保留既有死代码                         | 除非明确要求，否则超出本次职责 |
| 不要触碰你不理解的注释                 | Karpathy："副作用……与任务正交" |

判断标准：每一行更改都应该能追溯到用户请求。

### Goal-driven execution

定义可验证的成功标准。反复验证，直到通过。

| 模糊任务   | 可验证目标                         |
| ---------- | ---------------------------------- |
| "添加验证" | 为无效输入编写测试，然后让它们通过 |
| "修复错误" | 编写能重现问题的测试，然后让它通过 |
| "重构 X"   | 确保重构前后相同的测试通过         |
| "让它工作" | 要求明确能证明成功的信号           |

多步骤工作需要列出计划，并为每步给出验证方式：

```
1. [步骤] → 验证：[检查]
2. [步骤] → 验证：[检查]
3. [步骤] → 验证：[检查]
```

清晰的成功标准能支撑独立迭代。模糊标准会带来反复澄清。

---

## Scale Selection

策略随范围变化很大。选择匹配的重量级别：

| 规模                       | 编辑    | 策略                                        |
| -------------------------- | ------- | ------------------------------------------- |
| **琐碎**（配置、拼写错误） | 1-5     | Read -> Edit -> Verify -> Commit            |
| **小修复**                 | 5-20    | Grep error -> Read -> Fix -> Test -> Commit |
| **功能**                   | 50-200  | Plan -> 分层实现 -> 每层验证                |
| **子系统**                 | 300-500 | 任务规划 -> 分批调度 -> 分层推进            |
| **史诗级任务**             | 1000+   | 研究集群 -> 规格说明 -> 并行代理 -> 集成    |

**何时跳过计划：** 范围清晰、单文件更改、能用一句话描述的修复。

**何时计划：** 涉及多个文件、不熟悉的代码、方法仍未确定。

---

## Dependency Chain

按以下顺序构建。在全栈、Rust 和 monorepo 项目中验证过：

```
Types/Models -> Backend Logic -> API Routes -> Frontend Types -> Hooks/Client -> UI Components -> Tests
```

**全栈（Python + TypeScript）：**

1. 数据库模型 + 迁移
2. 服务/业务逻辑层
3. API 路由（FastAPI 或 tRPC）
4. 前端 API 客户端
5. 包装 API 调用的 React hooks
6. 消费 hooks 的 UI 组件
7. Lint -> typecheck -> test -> commit

**Rust：**

1. 错误类型（带 `#[from]` 的 `thiserror` 枚举）
2. 类型定义（结构体、枚举）
3. 核心逻辑（`impl` 块）
4. 模块连接（`mod.rs` 重新导出）
5. `cargo check` -> `cargo clippy` -> `cargo test`

**关键发现：**
数据库迁移通常在依赖它们的代码之后编写。前端驱动后端更改的频率，和后端驱动前端更改一样高。

---

## Verification Cadence

这是影响最大的单项实践。把验证节奏做好，其他环节会自然变顺。

| 关卡                   | 何时            | 速度           |
| ---------------------- | --------------- | -------------- |
| **Typecheck**          | 每 2-3 次编辑后 | 快（主要关卡） |
| **Lint (autofix)**     | 实现批次后      | 快             |
| **Tests (specific)**   | 功能完成后      | 中等           |
| **Tests (full suite)** | 提交前          | 慢             |
| **Build**              | 仅在 PR/部署前  | 最慢           |

### The Edit-Verify-Fix Cycle

最佳节奏：**3 次更改 -> 验证 -> 1 次修复**。这是最常见的成功模式。

高成本模式：**2 次更改 -> typecheck ->
15 次修复**（类型级联）。修改共享类型前，先 grep 所有消费者，可以预防这类情况。

**组合关卡节省时间：** `turbo lint:fix typecheck --filter=pkg`
一次性运行两者。把验证范围限定在受影响的包，避免验证整个 monorepo。

**实用技巧：**

- 在 `lint` 检查前运行 `lint:fix`，减少迭代
- 优先用 `cargo check`，少用 `cargo build`（快 2-3 倍，错误检测相同）
- 截断冗长输出：`2>&1 | tail -20`
- 用超时包装测试：`timeout 120 uv run pytest`

---

## Decision Trees

### Read vs Edit

```
本会话你编辑过的熟悉文件？
  是 -> 直接编辑（之后验证）
  否 -> 本会话读过它吗？
    是 -> 编辑
    否 -> 先读（79% 的快速修复以阅读开始）
```

### Subagents vs Direct Work

```
自包含且有明确交付物？
  是 -> 产生冗长输出（测试、日志、研究）？
    是 -> 子代理（保持上下文整洁）
    否 -> 需要频繁来回？
      是 -> 直接处理
      否 -> 子代理
  否 -> 直接处理（迭代改进需要共享上下文）
```

### Refactoring Approach

```
可以增量更改吗？
  是 -> 先移动，再整合（分开提交）
        新旧代码并存，测试通过后再删除旧代码
  否 -> 先分析阶段（并行审查代理）
        差距分析：逐个函数对比新旧实现
        把差距拆成专注任务处理
```

### Bug Fix vs Feature vs Refactor

| 类型         | 节奏                                                                     | 典型循环 |
| ------------ | ------------------------------------------------------------------------ | -------- |
| **错误修复** | Grep error -> Read 2-5 files -> Edit 1-3 files -> Test -> Commit         | 1-2      |
| **功能**     | Plan -> Models -> API -> Frontend -> Test -> Commit                      | 5-15     |
| **重构**     | Audit -> Gap analysis -> Incremental migration -> Verify parity          | 10-30+   |
| **升级**     | Research changelog -> Identify breaking changes -> Bump -> Fix consumers | 可变     |

---

## Error Recovery

**65% 的调试会话会在 1-2 次迭代内解决。** 其余 35% 容易进入 6+ 次迭代的调试螺旋。

### Quick Resolution (Do This)

1. 先阅读相关代码（79% 成功相关性）
2. 形成明确假设："问题是 X，因为 Y"
3. 做一次针对性修复
4. 验证修复有效

### Spiral Prevention (Avoid This)

1. **分离错误域** — 先处理所有类型错误，再处理测试失败。避免交错处理。
2. **三振规则** — 同一错误失败 3 次后：完全改变方法，或升级处理。
3. **级联深度 > 3** — 暂停，列出所有剩余问题，按依赖顺序处理。
4. **上下文腐化** — 约 15-20 次迭代后，`/clear`
   并重新开始。带有更好提示的干净会话，通常胜过堆满修正记录的旧会话。

### The Two-Correction Rule

如果同一问题已经修正两次，执行 `/clear` 并重启。累积的上下文噪音会降低准确性。

---

## Commit Cadence

边做边提交。每次提交记录一个已构建、已验证、已测试的逻辑块。每个会话通常包含多次小提交，避免把数小时的无关工作塞进一个巨型提交。宏观序列中的 COMMIT 步骤会回到 IMPLEMENT，继续处理下一个块；这个循环就是节奏。

### When to commit

| 触发器                            | 行动         |
| --------------------------------- | ------------ |
| 逻辑块完成且验证通过              | 立即提交     |
| 移动/重命名完成（在行为更改之前） | 提交（移动） |
| 行为更改通过验证（移动提交之后）  | 提交（更改） |
| 重构提取，调用者仍然通过          | 提交         |
| 添加了覆盖已修复错误的测试        | 提交         |
| 即将转向另一个关注点              | 提交当前块   |
| 验证在块中间失败                  | 不要提交     |
| 推测性或探索性编辑                | 不要提交     |

经验法则：如果审查者会希望把它作为单独 diff 阅读，它就应该是单独提交。

### Local style first

在任何仓库第一次提交前，先查看本地风格。仓库有自己的习惯——你的提交应该匹配它。

```bash
git log -10 --oneline
```

观察实际模式，并跟随它们：

| 模式                 | 示例                           | 跟随方式           |
| -------------------- | ------------------------------ | ------------------ |
| Conventional Commits | `feat(api): add token refresh` | `type(scope): msg` |
| Gitmoji              | `✨ Add token refresh`         | 前导 emoji + msg   |
| Ticket 前缀          | `[ENG-1234] Add token refresh` | 跟随括号风格       |
| 模块前缀             | `auth: add token refresh`      | 跟随分隔符         |
| 朴素                 | `Add token refresh`            | 无前缀，朴素       |

**跟随格式，保留质量。**
如果现有提交是简短的单行，你仍然要写清楚主题和正文——保持更高标准，同时匹配本地格式。如果没有明确模式，默认使用 Conventional
Commits。

### Conventional Commits (default)

格式：`type(scope): subject`。Scope 可选；改动范围明确时建议使用。

| Type       | When                       |
| ---------- | -------------------------- |
| `feat`     | 面向用户的新能力           |
| `fix`      | Bug 修复                   |
| `refactor` | 重构，无行为变化           |
| `perf`     | 性能优化                   |
| `test`     | 仅添加/更新测试            |
| `docs`     | 仅文档                     |
| `style`    | 格式、空白调整，无逻辑变化 |
| `chore`    | 工具、依赖、日常维护       |
| `build`    | 构建系统、打包             |
| `ci`       | CI/CD 配置                 |

### Message anatomy

**主题行：**

| 规则                     | 为什么                                           |
| ------------------------ | ------------------------------------------------ |
| 祈使语气                 | 使用 "Add token refresh"，避免 "Added" 或 "Adds" |
| ≤72 字符                 | 在 `git log --oneline` 和 PR 列表中显示整洁      |
| 无尾随句点               | 主题行按标题处理                                 |
| 无 emoji（Conventional） | 会影响解析器工具；如需 emoji，放在正文           |
| 跳过文件名               | diff 已经显示路径；主题行描述行为                |
| 具体                     | "Fix null deref in token refresh" 优于 "Fix bug" |

**正文（始终包含一个）：**

- 标题和正文均使用**中文**
- 解释**为什么**；diff 已经展示改了什么
- 在 ~72 个字符处换行，与主题用一个空行分隔
- 两句话通常就够了；必要时几个短段落
- 提及关键上下文：隐藏约束、相关问题、未来 bisect 需要的信息
- **无不确定语言。**
  禁止"可能"、"大概"、"也许"、"似乎"、"看起来"、"据推测"。你写了代码——陈述事实。提交前先读懂更改含义。

### The HEREDOC pattern

始终通过 HEREDOC 传递提交消息，以保留格式并避免 shell 引用错误：

```bash
git commit -m "$(cat <<'EOF'
fix(auth): guard against null session in token refresh

Refresh requests racing with logout were dereferencing a freed session
pointer, surfacing as a 500 with no log trail. Added an early return
that emits a single warn log so the failure mode is visible without
spamming on every refresh attempt.

EOF
)"
```

### Examples

| 不好                       | 为什么不好      | 好                                                |
| -------------------------- | --------------- | ------------------------------------------------- |
| `fix: bug`                 | 模糊            | `fix(api): resolve null pointer in token refresh` |
| `update stuff`             | 无类型，不具体  | `chore(deps): bump axios to 1.7.4`                |
| `WIP`                      | 不是提交消息    | `feat(auth): scaffold magic-link sign-in flow`    |
| `Added new file for users` | 文件名 + 过去时 | `feat(users): add bulk import endpoint`           |
| `feat: it works now`       | 没说什么工作了  | `feat(search): add fuzzy matching to user lookup` |

### Multi-agent hygiene

其他代理可能在并行工作。暂存要谨慎：

```bash
git status                # 先查看整体状态
git diff --staged         # 审查即将提交的内容
git add <specific-files>  # 只添加你亲自修改的文件
git commit -m "..."       # 消息用 HEREDOC
```

| 规则                                    | 为什么                                       |
| --------------------------------------- | -------------------------------------------- |
| 永远不要 `git add -A` 或 `git add .`    | 会带上其他代理的 WIP 和秘密                  |
| 永远不要 `git restore` 你没有修改的文件 | 可能丢弃另一个代理正在进行的工作             |
| 永远不要 `git push` 除非明确要求        | Push 由人类决定                              |
| 跳过规划文档、草稿文件、`.local.md`     | 这些文件不属于仓库                           |
| 提交前验证                              | 避免把失败状态写入历史，影响 git bisect 排查 |

---

## Anti-Patterns

| 反模式                                | 修复                           |
| ------------------------------------- | ------------------------------ |
| 20+ 次编辑不验证                      | 每 2-3 次编辑后验证            |
| 修复后缺少验证（73% 的修复！）        | 一次修复，一次验证，重复       |
| `fix -> fix -> fix` 链缺少检查        | 每次修复之间都验证             |
| 编辑前缺少阅读                        | 编辑前先阅读文件               |
| 凭记忆编写测试                        | 先阅读实际函数签名             |
| 更改共享类型前缺少消费者搜索          | 修改共享类型前 `Grep` 所有用法 |
| 在一次提交中混合移动和行为更改        | 先提交移动，再提交行为更改     |
| 调试螺旋超过 3 次尝试                 | 改变方法或升级处理             |
| 过早优化                              | 先保证正确性，测试通过后再优化 |
| 会话结束时一个巨型提交                | 每个逻辑块完成时提交           |
| 裸标题如 `fix: bug` 或 `update stuff` | 具体主题 + 解释原因的正文      |
| 为了"节省时间"跳过正文                | 始终包含正文——即使只有两句话   |
| 主题行包含文件名或路径                | 描述行为                       |
| 不确定语言（"可能修复"，"应该工作"）  | 陈述事实；读懂代码后再提交     |
| `git add -A` / `git add .`            | 仅暂存特定文件                 |
| 没有明确请求就 `git push`             | Push 由人类决定                |
| 默默选择一种解释                      | 呈现选项；选定前先询问         |
| "改进"与你的更改相邻的代码            | 保持精准；只触碰所要求的内容   |
| 触碰你不理解的注释                    | 保留它们                       |
| 为单次使用代码创建臃肿抽象            | 先写函数；重用时再抽象         |
| 模糊的"让它工作"目标                  | 先定义可验证检查               |

---

## Subagent Review

对于高风险更改，在验证通过后进入
`subagent-review`。这是 workflow 阶段，含义是使用当前 client 可用的独立审查上下文；不要把它绑定到固定 agent 名、固定工具名或某个单一 client。Pi 可使用当前可用的 subagent 系统，Claude/Codex 使用各自的子 agent 或 review 机制。如果当前执行者已经是 subagent，则跳过这一步。独立上下文能减少实现偏见，并捕获真实错误：迁移幂等性、调试日志中的 PII、空数组边缘情况、缺少批处理限制。

---

## What This Skill is NOT

- **Not a gate.** Don't follow all five phases for a typo fix. Scale selection exists for a reason.
- **Not a replacement for reading code.** This skill tells you HOW to implement, not WHAT to
  implement.
- **Not a planning tool.** Use `/hyperskills-plan` for task decomposition.
- **Not an excuse to skip tests.** "Verify" means running actual checks, not eyeballing the diff.
