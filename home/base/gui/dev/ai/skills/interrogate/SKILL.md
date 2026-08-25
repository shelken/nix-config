---
name: interrogate
description: 对抗性代码审查。触发词 "interrogate"、"对抗审查"、"challenge this"、"stress test this code"、"find blind spots"、"tear this apart"、"找盲点"、"撕裂这段代码"。派发多个 reviewer 子代理独立审查变更，主代理综合裁决，不自动改代码。
---

# Interrogate（对抗性审查）

分别派发多个 reviewer 子代理（不同模型）对同一份代码变更做对抗性审查。每个模型收到同样的意图和同样的审查标准。对抗信号来自模型多样性：模型在盲点、先验和推理模式上各不相同，跨模型共识是高置信度信号，单模型发现值得读但置信度较低。

产物是综合裁决报告。不自动改代码。

## 第 1 步，确定范围

从上下文识别要审查的对象：

- 用户指向具体文件或 diff，用那个
- 在功能分支上，跑 `git diff main...HEAD`（或合适的 base 分支）拿完整变更集
- 用户消息提到最近的工作，收集相关文件

打包 diff（或文件内容）加上 reviewer 理解代码所需的上下文。给 reviewer 上下文指针（issue 链接、关键文件路径），不要整段塞细节。

## 第 2 步，陈述意图

派发 reviewer 前明确写出意图：这段代码想达成什么。来源：

- 用户消息
- commit message
- PR 描述（若有）
- 代码本身

写一段清晰的意图。reviewer 挑战的是执行质量，不质疑意图本身。若不确定意图，先问用户。

## 第 3 步，派发 reviewer

用 `spawn-subagent list` 实时查看当前 `reviewer-<model>` 形式的 profile（reviewer-gpt、reviewer-glm、reviewer-gemini、reviewer-ds；不含裸 `reviewer`，那是通用审查代理）。把发现的全部 profile 写进 manifest，**一次 batch 派发**，同一份变更、同一套指令：

```json
{
  "task": "<按下方模板填充的完整 task，所有 reviewer 共享>",
  "agents": ["reviewer-gpt", "reviewer-glm", "reviewer-gemini", "reviewer-ds"]
}
```

```sh
spawn-subagent batch <manifest.json>
```

batch 的保证：校验先行（任一 profile 无效则零派发，不烧 token）；并发派发；每 agent 独立健康门（模型失效立即报 failed + 错误摘要，不影响其余）。输出每 agent 一行 `profile\tpane\tok|failed(reason)`，任一失败 exit 1。

**失效处理**：pi 已在同一会话内完成瞬时错误重试；failed 的 reviewer 由脚本自动关闭 pane 并输出分类，主代理当回合剔除即可，不派发替代。综合阶段按健康 reviewer 的结论继续；若全部失效，报告用户模型配置问题，不强行出裁决。

每个 profile 的 frontmatter `model`/`thinking`/`tools` 是唯一真相源，profile 本身不带审查标准。审查标准由 task 文本承载：读 `references/reviewer-prompt.md` 模板，填入意图、diff、`references/rubric.md` 与 `references/code-quality-review.md` 全文，作为 `<task>` 发出。同一份模板发给所有 reviewer。

`<task>` 内容（按模板填充）：

1. 对抗姿态：压力测试这段代码，找真问题，不鼓励、不改代码、只报发现；结论通过 intercom 回传，不写文件
2. 第 2 步的意图段落
3. 要审查的 diff：直接贴，或给文件路径让 reviewer 自行 `git diff` 读取
4. 审查标准：rubric.md + code-quality-review.md 全文
5. 理解代码所需的上下文指针（issue 链接、相关文件路径、架构说明）

reviewer 不得再派生子代理。

### 等待模式

batch 返回后主代理**立即结束当前回合**（不再调任何工具、不 sleep、不轮询）。健康 reviewer 的结论经 intercom 自动注入并唤醒主代理继续。这是唯一可靠姿势：herdr 对未聚焦 pane 只报 idle，无 working/done 区分，阻塞等待无信号。

计数只算 batch 输出中 ok 的 reviewer：应收到等于 ok 数的 intercom 结论，缺失任何一条都不开始综合（failed 的不指望回传）

每条结论消息第一行是 `[<agentName>]` 标签（由派发协议自动注入），用它对账到 profile；无标签的消息才用 batch 输出的 session/pane 映射反查。

## 模型多样性

对抗信号来自模型差异：同一份 diff 由多个模型独立审查，共识是高置信度信号，单模型发现降权。经济原则：不重复派发同一 profile；需要更多视角时新增 profile 而非重复派发。模型失效由 batch 健康门当回合发现并剔除，不会阻塞整轮审查。

## 第 4 步，综合

结论回来后构建统一图景：

1. **解析所有 findings**
2. **识别共识**：2+ 个模型独立提出的发现是最高信号
3. **识别单模型发现**：仍值得读，但相应降权
4. **去重**：不同模型对同一问题的不同表述，合并并标注由哪些模型提出
5. **记录分歧**：一个模型标记、另一个明确说相反的，是裁决的重要参考

## 第 5 步，主审裁决

你是主审，务实的资深工程师，不是中立传声筒。

读 `references/lead-judgment.md` 拿完整框架。reviewer 只看到代码切片，你有完整上下文（目标、约束、时间线、已讨论过的取舍）。积极用上下文过滤。

每个发现分桶：

- **Act on**：影响正确性/安全/可维护性的真问题，会阻塞真 PR
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
[驳回的发现，附简短理由。展示过滤了什么、为什么，让用户能推翻你的判断。]

### 一致性图
[模型间哪里一致、哪里分歧，模式说明什么。]