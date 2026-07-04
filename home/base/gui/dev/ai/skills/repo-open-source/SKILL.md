---
name: repo-open-source
description:
  把项目从 private 开源为 public 的完整流程。当用户说「开源项目」「仓库转
  public」「清理历史后开源」「private 转 public」或要把现有项目公开时使用。覆盖
  历史归档、敏感信息扫描、git history rewrite、分支清理的通用开源流程。
---

# repo-open-source

把项目从 private 开源为 public。核心矛盾:开源要暴露全部 git 历史,而历史里往往混着个人配置、临时文档、过时结构。直接改 public 等于把这些全公开。本流程用「双仓 + history rewrite」解决:private 仓存完整历史作只读归档,公开仓用 `git filter-repo` 抹除指定路径后开源。

## 前置确认

动手前必须和用户对齐三件事,否则会返工:

1. **private 仓是否仅作归档查看**。若是,双仓方案无同步负担,推荐;若 private 还要继续开发,双仓会分叉,改用单仓 rewrite。
2. **作者邮箱是否算隐私**。若邮箱公开,rewrite 只需清文件;若要隐藏邮箱,需额外 `--mailmap`。
3. **子项目/第三方目录去留**。如 `sub-dir/` 这类子项目、`.agents/skills/` 第三方 skill,逐一确认保留还是移除,不要擅自决定。

## SOP

### 1. 历史敏感扫描(只读,不改仓库)

开源前先摸清历史里有什么。这些命令只读,安全:

```bash
# git 历史中所有存在过的文件(全分支去重)
git log --all --pretty=format: --name-only | sort -u | sed '/^$/d'

# 中文文件名会被转义,用 core.quotepath=false 输出真实路径
git -c core.quotepath=false log --all --pretty=format: --name-only | sort -u | sed '/^$/d'

# 扫敏感文件:密钥/凭据/db/截图
git log --all --pretty=format: --name-only | sort -u | \
  grep -iE "\.(env|key|pem|p12|pfx|crt|cer)$|secret|credential|token|\.db$"

# 真实 .env 是否曾被提交(diff-filter=A 找新增)
git log --all --oneline -- '.env'
```

扫描目的:判断是「全量历史 rewrite」还是「只清少量文件」。多数项目敏感文件从未进过 git(`.gitignore` 挡住了),真正要清的是个人配置和过程产物。

### 2. private 归档仓

先建 private 仓保存完整历史,作为 rewrite 失败时的退路。

```bash
# 建 private 仓
gh repo create <user>/<project>-archive --private --description "<project> 完整开发历史归档(只读)"

# 加 remote 推全部历史
git remote add archive https://github.com/<user>/<project>-archive.git
git push archive --all
git push archive --tags
```

验证:远程分支数、tags 数、最新 commit 与本地一致。归档仓保留原始历史,后续查阅任何旧分支都在这里。

### 3. 清理远程遗留分支

origin 上的远程分支(已合并的 PR 分支、Renovate 分支等)开源前要清掉。逐个查合并状态再删:

```bash
# 列出非 main 的远程分支
git branch -r | grep origin/ | grep -v 'origin/HEAD' | grep -v 'origin/main$'

# 逐个查:是否已合并 main、领先/落后多少、最后活动
for b in <branch>; do
  ref="origin/$b"
  merged=$(git merge-base --is-ancestor "$ref" main 2>/dev/null && echo "已合并" || echo "未合并")
  ahead=$(git rev-list --count main.."$ref" 2>/dev/null)
  echo "$b | $merged | 领先$ahead"
done

# 删除
git push origin --delete <branch>
```

**注意 squash merge 陷阱**:走 squash merge 的分支,`--is-ancestor` 会显示「未合并」,但内容已进 main。判断依据看 commit message 是否带 PR 编号(`(#6)`),或看分支 tree 是否还是旧状态(如仍含 `.envrc`)。这类分支内容已进 main,可安全删。

### 4. 制定历史清除清单

把待清除路径写成清单文件,供 filter-repo 使用。每个路径必须满足:**当前 main 已不存在**(否则会误删当前文件)。

```bash
# 核对清单路径在当前 main 是否存在(必须全部「仅历史有」)
for p in <路径>; do
  git ls-files "$p" | head -1 && echo "⚠️ 当前main仍有: $p" || echo "✅ 仅历史: $p"
done
```

典型该清的类别:
- 个人配置:`.claude/` `.zed/` `.hindsight/` `.mcp.json` `.opencode/` `.beads/`
- 开发过程产物:`.planning/` `PLAN.md` `TODO.md` 临时 todos
- 已迁移的旧环境:`flake.nix` `flake.lock` `.envrc`
- v1 旧结构:`actions/`(根级)、根级散落 `.py`(已重构进 `src/` 的)
- 不开源的内部文档:`docs/plans/` `docs/needs/` `docs/superpowers/`

**根级 .py 陷阱**:`config.py` 这类清单项会误匹配 `src/.../config.py`。清单里写根级路径前,先确认它在历史中是否真存在于根级(`git log --all --name-only | grep "^config.py$"`,0 条则历史本就没有,从清单移除)。

### 5. filter-repo 副本实验(必须先做)

直接在主仓跑 filter-repo 不可逆。先 clone 副本验证。

```bash
# clone 副本(--no-local 走完整传输)
git clone --no-local <主仓> /tmp/<project>-rewrite-test

# 关键:--invert-paths 表示「排除」这些路径;漏了会变成「只保留」
git filter-repo --invert-paths --paths-from-file /tmp/cleanup_paths.txt --force

# 恢复工作区(filter-repo 会清空 working tree)
git checkout main
git reset --hard HEAD
```

验证四项,全过才动主仓:

```bash
# 1. 文件树与主仓一致(数量相同)
diff <(git ls-files | sort) <(cd <主仓> && git ls-files | sort)

# 2. 清单路径从历史消失(精确前缀匹配,不用 grep 模糊)
while IFS= read -r p; do
  case "$p" in \#*|"") continue;; esac
  git log --all --pretty=format: --name-only | sort -u | grep -E "^${p}" | wc -l
done < /tmp/cleanup_paths.txt
# 应全为 0

# 3. 历史起点保留
git log --reverse --oneline | head -1

# 4. 关键代码文件历史完整
git log --oneline -- main_v2.py | wc -l
```

### 6. 主仓执行 rewrite

副本验证通过后,对主仓执行相同命令。

```bash
# 确认工作区干净
git status --short

# 执行(filter-repo 会移除 origin remote,记录原地址备用)
git filter-repo --invert-paths --paths-from-file /tmp/cleanup_paths.txt --force

# 恢复工作区
git checkout main
git reset --hard HEAD

# 重连 origin(filter-repo 会移除它)
git remote add origin https://github.com/<user>/<project>.git
```

验证同副本四项。filter-repo 默认 `--prune-empty auto` 会剪除因重写变空的 commit,无需手动处理空 commit。

### 7. 推送开源仓 + 改 public

```bash
# force push 新历史覆盖旧历史
git push origin main --force

# tags 也要 force update(指向新哈希)
git push origin --tags --force

# 改 public
gh repo edit <user>/<project> --visibility public --accept-visibility-change-consequences
```

### 8. 清理本地旧分支

rewrite 后本地还留着大量旧历史分支(含被清除的文件)。全部已归档到 archive 仓,可删。但要先排查 worktree 关联分支。

```bash
# 查 worktree 关联的分支(这些要先处理 worktree)
git worktree list

# 失效 worktree 目录残留 + 关联,prune 清理
git worktree prune
rm -rf .worktrees/<失效目录>

# 删除非保留分支(排除 main 和 worktree 分支)
git branch | sed 's/^[* +]*//' | grep -vE '^(main|<worktree分支>)$' | xargs -I{} git branch -D {}

# 清理 filter-repo 拉取的 archive 远程跟踪引用(可选,留着便于查阅归档)
```

## 工具

- `git filter-repo`:nix-profile 装的,`git filter-repo --version` 验证。比 `git filter-branch` 快且安全。
- `gh`:建仓、改可见性、查远程分支。

## 踩坑

- **`--invert-paths` 不能漏**:`--paths-from-file` 默认是「保留」这些路径。漏写 `--invert-paths` 会变成只留清单里的文件,删光整个项目。副本实验能挡住这个错误。
- **grep 验证误报**:`git log --name-only | grep "config.py"` 会匹配到 `src/.../config.py`,误以为没清干净。验证用精确前缀 `grep -E "^${path}"`,且清单里的根级路径先确认历史中真存在。
- **squash merge 分支显示未合并**:走 squash merge 的功能分支,`--is-ancestor` 判断「未合并」,但内容已进 main。看 commit message 的 PR 编号或分支 tree 是否旧状态来判断,这类分支可安全删。
- **filter-repo 移除 origin**:这是它的设计行为(防止误推回原仓)。rewrite 后需手动 `git remote add origin` 重连。
- **worktree 分支删不掉**:`git branch -D` 报错因为分支被 worktree checkout。先 `git worktree prune`(目录已失效时)或 `git worktree remove`(目录还在时),再删分支。
- **子目录同名文件**:`flake.nix` 在根级和 `sub-dir/flake.nix` 是两个路径。清单写 `flake.nix` 是根级精确匹配,不会误清子目录。若要清子目录的,单独写 `sub-dir/flake.nix`。
