---
name: subagent-policy
description: 发起、审查或规划子代理工作时阅读该技能
---

# 子代理

**该skill适用于非Workflow场景下,Workflow使用独立的编排逻辑**

子代理由 `spawn-subagent` 脚本在 Herdr 窗格中启动（替代已禁用的 pi-subagents 插件），通过 `pi-intercom` 回传结论。

## 环境限制

- v1 仅支持 Herdr；非 Herdr（含 Kitty）脚本会停止并报告，不做降级。

## 发起子代理

```sh
spawn-subagent <profile> <slug> -- <task>
spawn-subagent resume <pane-id> -- <task> # 复用已有 agent pane 注入新任务，不重启；失败非零退出且不关闭该 pane
spawn-subagent list              # 列出所有 agent 的 name/model/thinking/tools/描述
spawn-subagent --check           # 派生 settings + 打印所有 agent 生效值，不启动
spawn-subagent close <pane-id>
```

`slug` 是任务语义标识（只含小写字母/数字/连字符；agent 名 `profile-slug-时间戳` 总长上限 32，时间戳为不截断的唯一后缀），用于 agent 命名（如 `explore-parse-errors-1786609381`）。

脚本会按布局推导新 pane 并启动 pi 子代理，最后输出 pane ID 供记录：

- 首个子代理：主 pane 右侧分列（`--ratio 0.55` 保留主 pane 55%）。
- 后续子代理：右侧最底部 pane 向下拆分，拆分后右列所有 pane 每次重新均分等高（避免累计失衡；pane 数量增多时单个 pane 必然更矮）。

### 等待模式

派发后主代理**立即结束当前回合**（不再调用任何工具、不 sleep、不轮询）：子代理结论经 intercom 自动注入并唤醒主代理继续处理，这是唯一可靠姿势

herdr 对未聚焦 pane 的 agent 全程仅报 idle（无 working/done 区分），阻塞等待无可靠信号，等待统一由 intercom 注入完成

### 预设表

每个 profile 对应 `~/.pi/agent/agents/<profile>.md` 模板（文件名小写匹配），frontmatter 的 `model` / `thinking` / `tools` 为**唯一真相源**，缺字段时回退 `subagent-config.json` 预设。profile 清单与生效配置实时获取，不在文档记录：

```sh
spawn-subagent list    # 全部 profile 的 name/model/thinking/描述
```

新增 profile：在 agents 目录新建 `<profile>.md`，最小 frontmatter 即可（`description` 一句中文用途 + `model` + `thinking` + `tools`），不要声明正文和 `exclude_extensions`（见排除清单）

> 脚本只解析 frontmatter，**不把 md 正文作为预设 prompt 注入**；协调 prompt 仅含回传协议和 task 原文。md 里的正文与 `prompt_mode: append` 仅供其他读取该 md 的插件使用。

### 排除清单

插件排除由 `subagent-config.json` 的 `exclude` 数组**全局统一生效**，不支持按 md 单独声明：所有子代理共用同一份派生 settings.json（每次 spawn 重写），per-md exclude 会被后续 spawn 覆盖，机制上无法成立。规范：只写插件短名（路径/仓库/npm 名的最后一段，scoped 包去 scope 取 name），如 `npm:@juicesharp/rpiv-todo` 写 `rpiv-todo`。

## 回传协议

- 子代理完成或受阻时，用 intercom 向主代理 session 发一条结论消息，格式由 task 描述，不设固定字段。
- 协调 prompt 由脚本自动生成：注入主代理 intercom session ID、回传引导、task 原文。

## 关闭子代理

```sh
spawn-subagent close <pane-id>
```

关闭 pane 并聚焦回主 pane。子代理 blocked / failed 时 pane 保留供用户检查，不自动关闭。

## 使用规则

- 除非有明确理由，不覆盖子代理已有的 model 和 thinking 配置。
- 禁止多次重复派发子代理，例如修复几行代码后重新派发。**经济原则**：非大问题/大修改不重新审查。
- 子代理不得继续派生子代理。
- reviewer 适合在大量变更/多轮任务之后使用。
- 发起子代理时，必须让其知道相关 issue/背景/上下文/前因后果/用户的完整意图；不要全部告知细节，告知其如何查询，例如直接给 issue 链接、重要文件路径
- 复审时可使用 intercom 与子代理进行交流; **主代理有任何审查方面的不同意见, 可直接与子代理辩论相关问题, 直到达成共识**
