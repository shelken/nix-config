---
name: subagent-policy
description: 发起、审查或规划子代理工作时阅读该技能
---

# 子代理

**该skill适用于非Workflow场景下,Workflow使用独立的编排逻辑**

子代理由 `spawn-subagent` 脚本在 Herdr 窗格中启动（替代已禁用的 pi-subagents 插件），通过 `pi-intercom` 回传结论

## 环境限制

- 仅支持 Herdr；非 Herdr（含 Kitty）脚本会停止并报告，不做降级

## 快速发起

命令完整用法见 `spawn-subagent -h`，按场景选择：

- 单个子代理：`spawn-subagent <profile> <slug> -- <task>`
- 多个子代理共享同一任务（如多模型对抗审查）：写 manifest 文件后 `spawn-subagent batch <manifest.json>`（文件路径，不支持内联 JSON 或 stdin）
- 给已存在的子代理 pane 追加新任务：`spawn-subagent resume <pane-id> -- <task>`
- profile 清单与生效配置（model/thinking/tools/描述）：`spawn-subagent list`
- 关闭子代理 pane 并聚焦回主 pane：`spawn-subagent close <pane-id>`

`slug` 是任务语义标识（小写字母/数字/连字符）；agent 名 `profile-slug-时间戳` 总长上限 32，超长 slug 自动截断，无需调用者计算。profile 名大小写不敏感，agent 名统一小写

脚本会按布局推导新 pane 并启动 pi 子代理，最后输出 pane ID 供记录：

- 首个子代理：主 pane 右侧分列（`--ratio 0.55` 保留主 pane 55%）
- 后续子代理：右侧最底部 pane 向下拆分，拆分后右列所有 pane 每次重新均分等高（pane 数量增多时单个 pane 必然更矮）

### 等待模式

派发后主代理**立即结束当前回合**（不再调用任何工具、不 sleep、不轮询）：子代理结论经 intercom 自动注入并唤醒主代理继续处理，这是唯一可靠姿势

herdr 对未聚焦 pane 的 agent 全程仅报 idle（无 working/done 区分），阻塞等待无可靠信号，等待统一由 intercom 注入完成

## 回传协议

- 子代理完成或受阻时，用 intercom 向主代理 session 发一条结论消息，格式由 task 描述，不设固定字段
- 协调 prompt 由脚本自动生成：注入主代理 intercom session ID、回传引导、task 原文

## 关闭子代理

`spawn-subagent close <pane-id>` 关闭 pane 并聚焦回主 pane；pane 不存在或已关闭时报错 exit 1。子代理 blocked / failed 时 pane 保留供用户检查，不自动关闭

## 使用规则

- 除非有明确理由，不覆盖子代理已有的 model 和 thinking 配置
- 禁止多次重复派发子代理，例如修复几行代码后重新派发。**经济原则**：非大问题/大修改不重新审查
- 子代理不得继续派生子代理（例外：受主代理明确委托执行子代理流程测试/审查协调时，以主代理身份行事）
- reviewer 适合在大量变更/多轮任务之后使用
- 发起子代理时，必须让其知道相关 issue/背景/上下文/前因后果/用户的完整意图；不要全部告知细节，告知其如何查询，例如直接给 issue 链接、重要文件路径
- 复审时可使用 intercom 与子代理进行交流; **主代理有任何审查方面的不同意见, 可直接与子代理辩论相关问题, 直到达成共识**

## 参考

### 健康门（模型失效立即感知）

派发不盲等：脚本在注入 task 后阻塞监听子代理会话文件（零模型调用），按确定性签名判别：

- 坏模型的 assistant 消息必为 `"stopReason":"error"` + 空 content + errorMessage（404/认证失败/配额耗尽等），恢复窗口耗尽后派发命令报错退出（exit 1，附具体错误摘要）
- 健康模型的 assistant 消息有内容（stopReason 为 toolUse/stop），exit 0 正常交给 intercom 等结论
- pi 遇瞬时错误（503 等）会自动重试，同一会话可 error 后恢复（实测 2-17s），因此首个 error 不判死：error 后有 15s 恢复窗口，窗口内出现新的健康 assistant 判健康，窗口耗尽仍无恢复才判失效
- 总超时 30s 无任何信号也按失败退出

即模型失效在派发命令的返回值里就能看到，主代理当回合即可处理失效模型，不会死等一个永远不回传的子代理。多个 agent 并发时健康门互相独立，一个失效只标记自己

失效后的处理：

- 瞬时故障（503 等）健康门内 pi 已自动重试过；若仍失败，允许关闭失败 pane（`spawn-subagent close <pane-id>`）后重试派发一次，二次失败则跳过/降权该模型
- 404（模型 id 错）/认证失败属配置问题，直接跳过，重试无意义

### batch 编排

manifest 格式：

```json
{
  "task": "共享任务全文（所有 agent 共用）",
  "agents": [
    "reviewer-ds",
    { "profile": "reviewer-glm", "slug": "glm" },
    { "profile": "reviewer-gemini", "slug": "gem", "task": "可选：覆盖共享 task" }
  ]
}
```

- `agents` 元素为字符串时 slug 自动取 profile 去掉 `reviewer-` 前缀；profile 的选择由调用者根据审查需求决定（`spawn-subagent list` 可见全部候选）
- **校验先行**：解析后先校验全部 profile/slug/task，任一无效则整体拒绝、零派发（防止一个配置错误烧掉全部 token）
- 派发分两阶段：串行启动+注入（pane 布局是累积操作），并发健康门（每个 agent 独立等待，互不阻塞）
- 输出每 agent 一行 `profile\tpane\tok|failed(reason)`，任一失败 exit 1；主代理按行处理失效者（跳过/降权），健康者照常等 intercom 回传

### 预设表

每个 profile 对应 agents 目录下 `<profile>.md` 模板（`spawn-subagent list` 实时可见），frontmatter 的 `model` / `thinking` / `tools` 为**唯一真相源**，缺字段时回退 `subagent-config.json` 预设

新增 profile：在 agents 目录新建 `<profile>.md`，最小 frontmatter 即可（`description` 一句中文用途 + `model` + `thinking` + `tools`），不要声明正文和 `exclude_extensions`（见排除清单）

> 脚本只解析 frontmatter，**不把 md 正文作为预设 prompt 注入**；协调 prompt 仅含回传协议和 task 原文。md 里的正文与 `prompt_mode: append` 仅供其他读取该 md 的插件使用

### 排除清单

插件排除由 `subagent-config.json` 的 `exclude` 数组**全局统一生效**，不支持按 md 单独声明：所有子代理共用同一份派生 settings.json（每次 spawn 重写），per-md exclude 会被后续 spawn 覆盖，机制上无法成立。规范：只写插件短名（路径/仓库/npm 名的最后一段，scoped 包去 scope 取 name），如 `npm:@juicesharp/rpiv-todo` 写 `rpiv-todo`
