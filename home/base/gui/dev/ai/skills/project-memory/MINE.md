# Mine 参考

本文件为 `mine` 模式的分析纪律与信号参考。主流程在 `SKILL.md` 的 Mine 节。

## 分析纪律（强制）

目标：从上下文里挖**可沉淀信息**。做不到就写「无」。禁止堆噪音表、session 流水账。

1. **模型归属到 message**：`error_model` + entry 的 `provider/model`；禁止整场 session 记到一个模型
2. **上下文裁决，禁止命令枚举定罪**：`behavior_risk` / `--preset-behaviors` 只是检索线索。命中后必须 `show` 前后文判断当轮是否真错。用户允许的 force、容器内 find、只读侦察、提问句、证据不足 → **不是错误**
3. **脚本价值 = 前后文**：用 Jump / `show --context` 读链，不用 mine 列表当终审
4. **降智嫌疑（尤其 GPT 系）**：若同时出现「明显忽略用户指令」+「突然低级错误/空转/格式自限/情绪对骂式复读」，标 **降智嫌疑**，**不要当错误展开分析，不要写 rule**（rule 纠不了降智）。只可在汇总里一行计数
5. **单次纠正 ≠ rule**：产品偏好、一次性指偏、证据不足的质疑句 → 丢弃。rule 需要可复用强制动作，且最好 ≥2 次非降智样本，或上下文证明系统性做错
6. **已在 auto-model-prompt / AGENTS 出现过的** → 不输出；最多内部记「执行失败」，不写进汇报正文
7. **汇报只保留有价值信息**（维度：项目 + 模型，不要 session 流水账）：
   - 建议 rule（简洁正文；无则「无」）
   - 用户习惯（跨上下文稳定偏好；无则「无」）
   - 降智嫌疑（模型 + 一句特征/计数；**不写 rule**）
   - 禁止：情绪词统计、已知禁令再清单、证据不足条目、降智过程复述
8. **默认不改** auto-model-prompt 文件，除非用户当轮明确要求写入

## 分析流程（重做）

```
mine 纠错/复读 → Jump 读上下文 → 分类 → 只留下「可沉淀」
分类桶：
  A 降智嫌疑 → 丢弃（可计数）
  B 已有 rule → 丢弃（不汇报）
  C 单次/非错误/证据不足 → 丢弃
  D 可沉淀 rule / 稳定用户习惯 → 写入对应表
```

## HARVEST

主路径只挖纠错/复读（跨项目，默认脱敏）。`--signals` 未写 `--since` 时默认 **15d**（全量：`--since all`）。preset 仅有**明确假设**时再加，命中仍须分类 A–D：

```sh
bun run --cwd "$PM_DIR" pm -- mine --since 15d --signals --limit 5 --all-projects \
  --signal-kind user_correction,repeated_user_prompt
# 有假设时再加 --preset-behaviors / --rule（不是定罪）
```

## 慢命令（slow_command）

列出 wall time 超阈值的 bash tool 调用，带 duration / command / exit / 上下文，供 agent 裁决是否低效。**不自动判定“低效”**：`just bd` / `cargo build` / E2E 测试是合理长命令，`find /` / 无超时 `ssh` 是不合理长命令——脚本只给候选，须 Jump 上下文裁决。

```sh
# 默认阈值 30s
bun run --cwd "$PM_DIR" pm -- mine --signals --signal-kind slow_command \
  --all-projects --since all --limit 5

# 提高阈值只看真长命令
bun run --cwd "$PM_DIR" pm -- mine --signals --signal-kind slow_command \
  --slow-threshold 120 --all-projects --since all --limit 5
```

耗时估算：`toolResult.timestamp − 父 assistant(toolCall) timestamp`。包含模型发出 tool 前的思考时间，但对长命令（≥30s）执行耗时主导，足够作为候选。多 bash 调用同轮次按出现顺序配对。

`--signals` 只返回有问题信号的 Session。排序：**技术向纠错优先**（`tech_score`），纯降智空转靠后；有 behavior 时 behavior 数仍最高。text 把 `degradation-like` 折叠成一行。

信号种类与分值：

- `user_correction`（3 分）：紧跟 Assistant 回答并包含明确纠正表达的用户消息。**分析主入口。**
- `repeated_user_prompt`（3 分）：Unicode 规范化后相同或相似度至少 0.86 的用户 Prompt；超过 500 字时只接受规范化后完全相同
- `behavior_risk`（4 分）：assistant 实际执行的 bash 命中 `--rule` / `--preset-behaviors`（需显式启用）。**仅候选。**
- `command_failure`（单条 2 分，session 总分最多计 2；text 默认折叠）：连续错误链

每个信号含 Entry ID、`error_model` / `recovery_model`、脱敏 Episode。信号是高召回候选，**不等于** Agent 一定犯错；必须主代理结合 Episode / `show` 裁决。

Episode / `--context` 仍不够时，再整页读该 session（**不是首次入口**）：

```sh
bun run --cwd "$PM_DIR" pm -- show --session "<session-id>" --transcript \
  --offset 0 --limit 50 --full-content --format json
```

用 `transcript_page.next_offset` 翻页直到 `null`。assistant 按各自 `model` 归属。仍不够再 `--all-branches`。

## 无报错怪癖与 behavior 分诊

**规则与频率由 agent 传入，脚本不替 agent 做判断。** 默认不启用 `behavior_risk`；需要时按假设传入规则，**命中后必须 `show` 上下文判断是否真错**，禁止用 regex 命中反推「模型又犯已知错误」。

行为扫描只看 **被执行的 bash 命令**（忽略 toolResult）；侦察类命令不计。`matched` 仅供核验，不是定罪。

有明确假设时才用 behavior 规则（**不是首次入口**）：

```sh
# 规则：id::regex::title（:: 分隔，避免正则里的 |）
bun run --cwd "$PM_DIR" pm -- mine --signals --all-projects \
  --rule 'git_add_all::\bgit\s+add\s+-A::禁止 add -A' \
  --signal-kind behavior_risk,user_correction

bun run --cwd "$PM_DIR" pm -- show --session <sid> --outline \
  --rule 'git_reset_hard::\bgit\s+reset\s+--hard\b::禁止 hard reset'
```

分诊要点：

- 首次只跑 HARVEST 那一条；不要一上来 preset
- `--rule` / `--preset-behaviors` / `--rules-file` 仅有假设时再加；命中须 Jump 上下文裁决
- `--correction-marker` 等 **追加** 默认词表；覆盖用 `--replace-markers`
- 同 rule 的 behavior 合并为一条并带 `count`
- 非法 `--signal-kind` / 坏正则 / 用 `|` 当分隔 → stderr 报错退出
- 仅要 `behavior_risk` 却不传规则 → 直接报错

其余 flag（`--repeated-threshold` / `--min-prompt-len` / `--episode-radius*` / `--no-*-filter` / `--outline-max-*` / `--context` / `--max-chars` 等）见 `mine --help` 与 `show --help`。
