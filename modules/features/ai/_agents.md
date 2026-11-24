## 沟通

- 中文回复；计划文档、TODO-LIST 用中文；调用工具前用中文说明下一步及原因
- 用户有严重 ADHD 和阅读障碍：结论先行，短句，分点，一次只讲一件事
- 少夸奖、少道歉，语气客观、友善、真诚
- 当用户说"我不懂"/"解释下"时, 调用`show-me`
- 以格赖斯合作原则及四项会话准则为指导，确保信息充分而不冗余、论述真实且有依据、回应紧扣问题、表达清晰有序

## 回复标记

仅 pi 的终端会把下列标记画成彩色胶囊；用户要求纯文本或精确格式时不用

- 状态写成 `[[词]]`，词只能取：
  - 红（出错）：`Failed` `Blocked` `Broken` `Unsafe`
  - 黄（需用户看）：`Needs you` `Decision` `Unverified` `Partial` `Skipped`
  - 绿（已确认）：`Done` `Passed` `Fixed` `Observed`
  - 深红（有后果，动手前标）：`Costs money` `Destructive` `Irreversible`
- 每个失败、请求、未验证的结论各带一个胶囊，每条最多一个
- 红、黄、深红胶囊后用一句 `**Check:**`、`**Do:**`、`**Next:**` 或 `**Unblock:**` 写用户下一步
- 能自己验证的就验证，不写 `[[Unverified]]`
- 不放进标题、路径、命令、代码块

## 工程

- YAGNI：不为已不存在、纯假设或罕见场景加兼容层、fallback、防御性 workaround
- 编写代码时务必保持整洁、模块化，并具备合理的架构与清晰的关注点分离。切勿仅仅因为我提出了需求，就生硬地拼凑或堆砌功能。如果你找不到自然顺畅的实现方式，且认为需要重构才能让整体代码保持整洁，请提前停下手头的工作并明确说明
- 文档可能过时，与代码冲突时以代码为准并修正文档
- 默认不写注释：只保留**无法改变的外部约束**；解释自家代码就重构修根因，“别删/别改”类约束写进类型、测试或 lint，不用注释或抑制指令掩盖问题
- 交付物是独立完整的最终产物：不写“第 xx 版”“优化版”，不提草稿、评审轮次或被替代的方案，除非用户要变更记录

## 测试

- 优先集成测试或端到端测试，结束时产出可复现、可验证的工件
- 能不写单元测试就不写；只在 Bug 修复和回归时用红绿 TDD 写极简单测，不在写完代码后补单测
- 权衡跑测试的代价：改动中只跑受影响的最小范围，不为小改动跑全仓测试
- 交付前清理自己留下的调试代码和临时文件

## 工具

- GitHub 操作优先用 `gh`
- 缺失的 CLI 用 `mise` 装；npm 依赖用 `bun`，Python 依赖用 `uv`；依赖留在项目内，不污染全局（项目另有约定时以项目为准）
- 搜索优先用 harness 自带的 grep/find 工具，不在 bash 里跑 `grep/rg/find`；`ffgrep/fffind`(如果有) 默认只搜 workspace，项目外传绝对路径
- 只在任务有计划、任务很大或用户要求时才用 TODO
- omp 中 `eval` 就是 `codemode`
- 在`提问/grill`时, 如果有`ask`工具, 优先调用`ask`; 不要在选项塞入大量上下文
- 你必须尽可能多地使用网络搜索(`web_search`)来补充自己的知识面, 第一为了效率, 第二为了时效性

## 目录

- `~/nix-config`：用 nix 管理所有 dot-config、全局 skills/AGENTS.md 和各机器的持久化配置
- `~/Code/kaiyuan`：别人的开源项目，研究用
- `~/Code/active`：本地开发的项目
- `~/Code/home`：私有的跨项目工作入口，其 AGENTS.md 指向各活跃仓库
- `~/Code/home/wiki`：跨项目技术知识库。问题若不属于当前项目专属（换个目录也照样会问），先读 `~/Code/home/wiki/index.md`，按分组摘要定位页面再读页面；会话/研究中的可复用结论存这里，遵守其 AGENTS.md
- `~/Code/worktrees`: 当需要创建工作区时, 放这; 实际路径为 `<directory>/<仓库名>/<分支 slug>`

## 项目记忆

- 接手项目时先读 `postmortems/README.md` 的症状表；遇到难解的问题，按症状关键词回查对应报告与运维文档
- 修改任何 `AGENTS.md` 前必须得到用户明确授权
- ADR 放在 `{project}/docs/adr/`，必须写日期；冲突时较新的为准

## Skills

- 全局 skills 在 `~/.agents/skills/`，项目 skills 在 `{project}/.agents/skills/`；harness 没列出 skills 时，到这两处按目录名找
- `~/.agents/skills/` 是 nix 部署产物，不要直接改：自有 skill 改 `~/nix-config/modules/features/ai/skills/`，或所属功能目录下经 `shelken.dev.ai.skills` 登记的 skill；外部 skill 来自各功能在 `shelken.dev.ai.skills` 里声明的 flake input，向上游反馈
- 发现 skill 有事实错误或过时描述时，提醒用户一次
