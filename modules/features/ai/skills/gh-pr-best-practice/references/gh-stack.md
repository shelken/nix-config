# gh stack 操作手册

GitHub 原生 stacked PRs 的命令行：把有依赖的一串改动拆成链式 PR，逐个 review，最后整条原子合并到默认分支。官方文档：<https://gh.io/stacks>，命令帮助：`gh stack <命令> --help`

本文记录在本仓库把一次大重构拆成 4 个 PR 时实际用到的流程。标「未实操」的部分只依据命令帮助，没有跑过

## 何时用

- 改动有先后依赖，一个 PR 太大无法 review：用栈，每层只显示自己的 diff
- 彼此独立、可以任意顺序合并：各开普通 PR，不要硬凑栈
- 所有分支必须在同一个仓库里，不支持跨 fork

分层原则：每层能单独构建、单独验证，下层不依赖上层。这次的切法是「基线对齐 → 结构整理 → 行为不变的语言迁移」，每层都在真环境里验证过再叠下一层

## 前置

- `gh stack` 是 gh 扩展，本仓库由 Nix 安装（`modules/features/dev/gh.nix`），不要手动 `gh extension install`
- 第一次调用 `gh stack` 时 gh 会自动安装缺失的扩展，没有确认提示；在没有 Nix 管理的机器上先问用户
- 所有命令要在仓库目录里执行；在 `/tmp` 里 `cd` 过去再 `gh stack …` 会报 `not a git repository`

## 建栈

```bash
# 已有分支（已经有 PR）作栈底：直接接管，PR 保留
gh stack init refactor/feature-a
#   ✓ Adopted 1 branch: main ← refactor/feature-a   Found PRs for 1 of 1 branch.

# 在栈顶新加一层：创建并切到新分支，不带提交
gh stack add refactor/feature-b
# 然后照常 git commit（pre-commit 钩子照常跑）。也可以 gh stack add -Am "msg" <分支> 一步提交
```

- 已有 PR 的分支不要改名：改 head 分支名会让 GitHub 关掉该 PR
- 栈底分支的 base 是默认分支；`gh stack view` 看全貌，`--short` 一行一层，`--json` 给脚本用

## 提交成 PR

```bash
gh stack submit --auto          # 原子推送所有分支，给没有 PR 的层创建 PR，并在 GitHub 上建栈
gh pr edit <N> --title "…" --body-file body.md   # 再逐个改标题和正文
```

- `--auto` 不开编辑器，标题是自动生成的，**必须**再改；新 PR 默认是草稿，`--open` 直接标为可评审。草稿不能合并栈，改完正文后用 `gh pr ready <N>` 转为可评审
- 创建后每个 PR 的 base 是它下面一层的分支，栈底是默认分支；各 PR 的 diff 只含自己那层
- 已有 PR 的层显示 `is up to date`，不会被重建
- 标题 scope 沿用 `gh pr list --state merged` 里的惯例；正文按 `pr` 技能的模板写，并说明每层依赖哪一层。公开仓库的 PR 里不要写个人路径、IP、设备环境数据

## main 前进或下层变了

`gh stack view` 里层名后出现 `⚠` 表示需要 rebase。

```bash
gh stack rebase                 # 自下而上级联 rebase，先拉 trunk
gh stack push                   # 原子推送，rebase 过的分支用 --force-with-lease
# 或者一步：gh stack sync       # fetch + rebase + push + 同步 PR 状态
```

改下层的内容：

```bash
gh stack down                   # 或 gh stack switch / bottom 切到要改的层
# 改、提交
gh stack rebase --upstack       # 只把改动传给它上面的层（未实操）
gh stack push
gh stack top                    # 回到栈顶
```

- rebase 会改写 commit 哈希，这是「不要改写历史」规则的例外；推送必须经 `gh stack push` 或 `sync`，不要手写 `git push --force`
- rebase 之后之前的验证证据严格说不再覆盖新哈希。上游新增的改动与本栈无关时，重跑构建、单元测试和最短的冒烟即可；有重叠就重跑完整验证
- 一次 rebase 出冲突时 gh stack 会停下，解决后 `git rebase --continue`，再 `gh stack rebase` 接着往上

## 合并（未实操）

```bash
gh stack merge                  # 当前栈，向导里选合并到哪一层、合并方式
gh stack merge <PR 号> --yes    # 合并到指定 PR 为止（含其下所有层），不交互
```

- 选中那层及其下所有层在一个原子操作里合并：任何一个不能合并，全部不合
- 合并前只检查 PR 是 open 且非草稿；分支保护与规则由 GitHub 在合并时评估，失败会原样报告；栈不支持绕过合并要求
- 基础分支用了合并队列时，栈整体进队列

## 导航与维护

| 命令 | 作用 |
| --- | --- |
| `gh stack view` | 看栈，`⚠` 需要 rebase |
| `gh stack top` / `bottom` / `up` / `down` / `switch` | 在栈内切换分支 |
| `gh stack checkout <栈号\|PR 号\|分支>` | 在别的机器上拉下整个栈 |
| `gh stack modify` | 交互式重排或拆分层 |
| `gh stack link <分支\|PR 号…>` | 不用本地跟踪，直接把已有 PR 在 GitHub 上连成栈（给用 jj、git-town 等外部工具的人） |
| `gh stack unstack` | 拆掉栈（本地和 GitHub），PR 本身保留；已合并或在队列里的 PR 仍保持在栈中 |

## 本仓库里的注意点

- 和 `gh-pr-best-practice` 的其余规则一致：不 amend，修正用新提交；`Co-Authored-By` 不自行增删
- 提交信息、PR 标题用 `类型(范围): 中文简述`
- 栈里每层的提交都要过 pre-commit 钩子；推送前用 `gh stack view` 确认没有 `⚠`
