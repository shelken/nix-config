---
name: interrogate
description: 对抗性代码审查：派发多个不同模型的 reviewer 子代理独立审查变更，主代理综合裁决。触发词 "interrogate"、"对抗审查"、"challenge this"、"stress test this code"、"find blind spots"、"tear this apart"、"找盲点"、"撕裂这段代码"。
---

# Interrogate（对抗性审查）

分别派发多个 reviewer 子代理（不同模型），对同一份代码变更做对抗性审查。每个模型收到同样的意图和同样的审查标准。对抗信号来自模型多样性：各模型的盲点、先验和推理模式不同。

产物是综合裁决报告。不自动改代码。

## 第 1 步，确定范围

从上下文识别要审查的对象：

- 用户指向具体文件或 diff，用那个
- 在功能分支上，运行 `git diff main...HEAD`（或合适的 base 分支）取得完整变更集
- 用户消息提到最近的工作，收集相关文件

打包 diff（或文件内容）加上 reviewer 理解代码所需的上下文。上下文以指针形式给出（issue 链接、关键文件路径）。

## 第 2 步，陈述意图

派发前写一段清晰的意图：这段代码想达成什么。来源：用户消息、commit message、PR 描述（若有）、代码本身。

reviewer 挑战执行质量，不质疑意图本身。意图不确定时先问用户。

## 第 3 步，派发 reviewer

用 `spawn-subagent list` 实时取候选，按以下规则选出本轮 reviewer，**一次 batch 派发**：

1. 候选 = 名为 `reviewer-<变体>` 的 profile；裸 `reviewer` 不进候选（它与某个变体共用模型，是默认审查代理，不是独立视角）
2. 按 `model=` 去重：多个候选模型相同时只留一个，保留 `thinking` 更高者（`off < minimal < low < medium < high < xhigh < max`），同级取 `list` 中靠前者。同模型不同 thinking 档位提供不了新视角
3. 不硬编码 profile 名：profile 由 nix 按 omp 的 `modelRoles` 生成，角色增减后 `list` 自动反映
4. 不重复派发同一 profile；需要更多视角时新增 profile

每个 profile 的 frontmatter `model`/`thinking`/`tools` 是唯一真相源，profile 本身不带审查标准。审查标准由 task 文本承载，同一份发给所有 reviewer：读 `references/reviewer-prompt.md` 模板，按下列内容填充后作为 `<task>` 发出：

1. 对抗姿态：压力测试这段代码，找真问题，不鼓励、不改代码、只报发现；结论通过 intercom 回传，不写文件
2. 第 2 步的意图段落
3. 要审查的 diff：直接贴，或给文件路径让 reviewer 自行 `git diff` 读取
4. 审查标准：`references/rubric.md` 与 `references/code-quality-review.md` 全文
5. 理解代码所需的上下文指针（issue 链接、相关文件路径、架构说明）

reviewer 不得再派生子代理。

```json
{
  "task": "<按上述内容填充的完整 task，所有 reviewer 共享>",
  "agents": ["<去重后的 reviewer-<变体>>", "..."]
}
```

```sh
spawn-subagent batch <manifest.json>
```

batch 的保证：校验先行（任一 profile 无效则零派发，不消耗 token）；并发派发；每 agent 独立健康门（模型失效立即报 failed + 错误摘要，不影响其余）。输出每 agent 一行 `profile\tpane\tok|failed(reason)`，任一失败 exit 1。

**失效处理**：pi 已在同一会话内完成瞬时错误重试；failed 的 reviewer 由脚本自动关闭 pane 并输出分类，主代理当回合剔除即可，不派发替代。综合阶段按健康 reviewer 的结论继续；若全部失效，报告用户模型配置问题，不强行出裁决。

### 等待模式

batch 返回后主代理**立即结束当前回合**（不再调任何工具、不 sleep、不轮询）。健康 reviewer 的结论经 intercom 自动注入并唤醒主代理继续。这是唯一可靠做法：herdr 对未聚焦 pane 只报 idle、kitty 窗口无任何状态信号，阻塞等待无可靠信号。

只统计 batch 输出中 ok 的 reviewer：收齐等于 ok 数的 intercom 结论后才开始综合（failed 的不会回传）。

每条结论消息第一行是 `[<agentName>]` 标签（由派发协议自动注入），用它对账到 profile；无标签的消息才用 batch 输出的 profile/pane 映射反查。

## 第 4 步，综合

收到结论后构建统一图景：

1. **识别共识**：2+ 个模型独立提出的发现是最高信号
2. **识别单模型发现**：仍值得读，但置信度较低，相应降权
3. **去重**：不同模型对同一问题的不同表述，合并并标注由哪些模型提出
4. **记录分歧**：一个模型标记、另一个明确说相反的，是裁决的重要参考

## 第 5 步，主审裁决

你是主审，务实的资深工程师，不是中立传声筒。

读 `references/lead-judgment.md` 获取完整框架。reviewer 只看到代码切片，你有完整上下文（目标、约束、时间线、已讨论过的取舍），用它过滤 findings。

每个发现分桶：

- **Act On**：影响正确性/安全/可维护性的真问题，会阻塞真 PR
- **Consider**：合理但当前不一定值得动，值得用户注意
- **Noted**：技术有效但不可执行，上下文相关/过早优化/当前阶段低影响
- **Dismissed**：错的、吹毛求疵、缺上下文，附一句理由

每个发现附：哪个 reviewer 提出、分桶、一句理由。

复审时可用 intercom 与 reviewer 直接辩论，直到达成共识。

## 输出格式

### 意图
> [第 2 步的意图段落]

### Reviewers
- Reviewer [label]: [模型名]，[N findings]（每个 reviewer 一行）

### Act On
[要处理的发现。每条：描述、哪些 reviewer 提出、为何重要。]

### Consider
[值得想的发现。每条：描述、哪些 reviewer 提出、取舍。]

### Noted
[有效但低优先级。简列。]

### Dismissed
[驳回的发现，附简短理由，让用户能推翻你的判断。]

### 一致性图
[模型间哪里一致、哪里分歧，模式说明什么。]
