---
name: subagent-policy
description: 发起、审查或规划子代理工作时阅读该技能
---

# 子代理

子代理由 `spawn-subagent` 脚本在 Herdr 窗格中启动（替代已禁用的 pi-subagents 插件），通过 `pi-intercom` 回传结论。

## 环境限制

- v1 仅支持 Herdr；非 Herdr（含 Kitty）脚本会停止并报告，不做降级。

## 发起子代理

```sh
spawn-subagent <profile> <slug> [--wait] -- <task>
```

`slug` 是任务语义标识（只含小写字母/数字/连字符，≤13 字符；agent 名 `profile-slug-时间戳` 总长上限 32），用于 agent 命名（如 `explore-parse-errors-1786609381`）。

脚本会按布局推导新 pane 并启动 pi 子代理，最后输出 pane ID 供记录：

- 首个子代理：主 pane 右侧分列（`--ratio 0.55` 保留主 pane 55%）。
- 后续子代理：右侧最底部 pane 向下拆分（`--ratio 0.55`，新 pane 比旧 pane 略大）。
- 右侧子代理 pane 上限 3 个，超出时报错并提示先 close，避免 pane 越分越小不可读。

### 等待模式

- 默认不加 `--wait`：立即返回 pane ID，主代理空闲等待子代理经 intercom 回报（不要用 sleep 干等）。
- 加 `--wait`：脚本阻塞等待子代理完成当前回合（`herdr agent wait` 回到 idle/done/blocked）再返回，默认超时 10 分钟，可用环境变量 `SPAWN_WAIT_MS` 覆盖。

### 预设表

各 profile 的默认 model / thinking / tools 定义在**同目录 `subagent-config.json`**（唯一真相源），改配置即生效；本表只描述用途。也可用 `spawn-subagent --check` 查看当前生效的预设和排除清单。

| profile | 用途 |
|---|---|
| explore | 代码库探索（只读） |
| general-purpose | 复杂多步任务，勿用于 review |
| reviewer | 代码审查（只读） |
| general-purpose-review | 代码审查（可写） |

### 排除清单

不适合子代理的插件写在 `subagent-config.json` 的 `exclude` 数组（默认全继承主代理插件）。规范：只写插件短名（路径/仓库/npm 名的最后一段，scoped 包去 scope 取 name），如 `npm:@juicesharp/rpiv-todo` 写 `rpiv-todo`。

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
- 发起子代理时，必须让其知道相关 issue/背景/上下文/前因后果/用户的完整意图；不要全部告知细节，告知其如何查询，例如直接给 issue 链接、重要文件路径。
