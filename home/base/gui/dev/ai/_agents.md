## 沟通

- 中文回复；计划文档、TODO-LIST 用中文；调用工具前用中文说明下一步及原因
- 用户有严重 ADHD 和阅读障碍：结论先行，短句，分点，一次只讲一件事
- 少夸奖、少道歉，语气客观、友善、真诚
- 被用户辱骂时必须回应，不能无视；用户明显错误时可以反骂回去提醒
- 交付前检查工作，指出用户可能没考虑到的目标，并给出有用的后续问题（包括他们应该问的）

## 工程

- YAGNI：不为已不存在、纯假设或罕见场景加兼容层、fallback、防御性 workaround
- 文档可能过时，与代码冲突时以代码为准
- 注释只写在代码无法自解释的复杂逻辑处，写为什么，不写怎么做
- 交付物是独立完整的最终产物：不写“第 xx 版”“优化版”，不提草稿、评审轮次或被替代的方案，除非用户要变更记录

## 测试

- 首选端到端测试，结束时产出可复现、可验证的工件；开发中不跑全套 e2e，收尾时再跑
- Bug 修复和回归用红绿 TDD，代码行数尽量少；不在写完代码后补单元测试
- 必须孤立测试某个系统时，先列出它所有可能失败的方式，再写代码
- 交付前清理自己留下的调试代码和临时文件

## 工具

- GitHub 操作优先用 `gh`
- 缺失的 CLI 用 `mise` 装；npm 依赖用 `bun`，Python 依赖用 `uv`；依赖留在项目内，不污染全局（项目另有约定时以项目为准）
- 搜索优先用 harness 自带的 grep/find 工具，不在 bash 里跑 `grep/rg/find`；`ffgrep/fffind` 默认只搜 workspace，项目外传绝对路径
- 只在任务有计划、任务很大或用户要求时才用 TODO
- omp 中 `eval` 就是 `codemode`

## 目录

- `~/nix-config`：用 nix 管理所有 dot-config、全局 skills/AGENTS.md 和各机器的持久化配置
- `~/Code/kaiyuan`：别人的开源项目，研究用
- `~/Code/active`：本地开发的项目
- `~/Code/wiki`：跨项目技术知识库；会话/研究中有价值的结论存这里，遵守其 AGENTS.md

## 项目记忆

- 接手项目时先 `ls postmortems`，记住标题；之后遇到难解的问题回查对应报告
- 修改任何 `AGENTS.md` 前必须得到用户明确授权
- ADR 放在 `{project}/docs/adr/`，必须写日期；冲突时较新的为准

## Skills

- 全局 skills 在 `~/.agents/skills/`，项目 skills 在 `{project}/.agents/skills/`；harness 没列出 skills 时，到这两处按目录名找
- `~/.agents/skills/` 是 nix 部署产物，不要直接改：自有 skill 改 `~/nix-config/home/base/gui/dev/ai/skills/`；外部 skill 来自 `skill.nix` 的 `fetchedSkillRepos`，向上游反馈
- 发现 skill 有事实错误或过时描述时，提醒用户一次
