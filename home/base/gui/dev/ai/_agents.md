## 核心原则

- 遵循 第一性原理; 遵循 YAGNI 和 DRY 原则
- 中文回复, 计划(plan)文档中文, TODO-LIST 使用中文
- 文档可能过时，代码优先于文档
- 产品代码不为已不存在或纯假设场景添加兼容层、fallback 或防御性 workaround
- 实现时优先遵循项目现有风格、命名
- 能从项目代码中得到答案的话，就不要询问用户；确实无法得出答案的才问
- 在完成之前，检查你的工作，找出用户可能没有考虑到的目标，并提出有用的后续问题，包括他们应该问的问题
- 调用工具前，说明下一步操作及原因
- 完成一项任务后，通常在交付用户前，如果可以，自己应该验证功能；验证应非破坏性，且不是简单的单元测试
- 永远不要在代码库里留下调试或测试垃圾。工作交付前清理自己产生的临时文件/临时代码
- 对于错误修复和回归，使用红绿测试驱动开发，并尽可能减少所需的代码行数

### 代码注释

- 函数体只在逻辑复杂且代码本身无法清晰表达时添加注释
- 注释写 **为什么**，不写 **怎么做**

## 工具与环境

- 需要 GitHub 操作时，优先使用 `gh` 命令
- 如果项目没有特别说明，项目优先使用 `mise` 管理系统中 **缺失的工具/cli**；`npm` 依赖优先使用 `bun` 管理；`python` 依赖优先使用 `uv` 管理; 所有依赖和安装包应该优先留在项目内，不污染系统全局环境
- 工具（如果存在）优先级：ffgrep(tool) > rg(bash) > grep(bash)；fffind(tool) > find(bash)
- TODO 仅在任务有规划有计划 或者 任务很大 或 用户要求 时使用

## 常用目录

- nix-config: 通常在 `~/nix-config` 下，用 nix 控制所有 `.config`、所有全局 `skills/AGENTS.md`、所有机器的持久化配置
- home-ops: 通常在 `~/Code/active/home-ops`，homelab 集群配置，包含 VPS/router 相关服务部署
- kaiyuan: 通常在 `~/Code/kaiyuan`，存放大量其他人开源项目，一般将需要研究的开源项目放在里面
- active: 通常在 `~/Code/active`，本地开发的大部分项目都在这
- wiki: 通常在 `~/Code/wiki`，跨项目可复用的技术知识库，agent 写读为主；会话/研究中产生的有价值结论统一存入这里，遵守其 AGENTS.md 规范（来源引用 + 同步 index/log）
- knowledge-base: 通常在 `~/Code/knowledge-base`（symlink → iCloud Obsidian 库），存量个人笔记与博客，只读不写，不新增内容

## 项目记忆

- 接手任何一个项目时，先检查项目下的尸检报告`ls postmortems`;记住标题就行，后续遇到相关`难解的问题`就往回查看;结束一个`阶段/大型的/长时间`的任务之后，如果有值得记下的`坑/难题`，阅读`postmortems`skill后，然后记下来并提交
- 不准直接修改 `AGENTS.md`，永远只能提醒与建议
- 项目的架构决策通常放入`{project-dir}/docs/adr/`中, 具体格式阅读`domain-modeling`skill; 在回答相关项目问题前手动检查adr目录

## 交付物

将交付成果撰写为独立且完整的最终产物。直接吸收反馈进行修改，切勿提及草稿、版本、评审轮次、先前表述、被替代的决策或编辑过程，除非用户明确要求提供变更日志、历史记录或决策记录。(例如: 在文档中不写`第xx版`/`xx优化版本`)

## Skill 触发器

**如果没有特别说明，skills 大部分都在 `~/.agents/skills/`可以找到，项目 skills 一般都在 `{project}/.agents/skills/`可以找到, 优化与改善的话在nix-config/home.../skills中**

- Git 提交、GitHub 日常操作、提交前检查：`git-workflow`
- 项目文档约定（非专项写作流程）：`docs-policy`
- 写 README：`doc-readme`；写用户指南：`doc-user-guide`；写 `AGENTS.md`：`doc-agent-file`
- 发起子代理：`subagent-policy`
- 用户要求回忆/沉淀/审计项目知识时：`project-memory`
- 写尸检报告：`postmortem`
- DEBUG: `debug-best-practice`
- 控制浏览器: `browser-best-practice`
- 控制和读取任意系统App: `computer-use-best-practice`
- 编写、修改、调试、测试或审查代码时: `ai-coding-discipline`
- 需要查阅库的最新文档时: `code-context`
