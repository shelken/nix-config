---
name: repo-open-source
description: 把 private 项目开源为 public 的完整流程,覆盖历史归档、敏感信息扫描、git filter-repo 重写历史和分支清理。
disable-model-invocation: true
---

# repo-open-source

把项目从 private 开源为 public 前,需要检查完整 Git 历史中的个人配置、临时文档和过时结构。默认采用「双仓 + history rewrite」:private 仓作为完整历史的只读归档,公开仓用 `git filter-repo` 清除指定路径后再开源。

## 前置确认

动手前必须和用户对齐三件事,否则会返工:

1. **private 仓是否仅作归档查看**。若是,双仓方案无同步负担,推荐;若 private 还要继续开发,双仓会分叉,改用单仓 rewrite。
2. **作者邮箱是否算隐私**。若邮箱公开,rewrite 只需清文件;若要隐藏邮箱,需额外 `--mailmap`。
3. **子项目/第三方目录去留**。如 `sub-dir/` 这类子项目、`.agents/skills/` 第三方 skill,逐一向用户确认保留还是移除。

## 工具

- `git filter-repo`:nix-profile 装的,`git filter-repo --version` 验证。比 `git filter-branch` 快且安全
- `gh`:建仓、改可见性、查远程分支

## SOP

### 1. 历史敏感扫描(只读,不改仓库)

```bash
# git 历史中所有存在过的文件(全分支去重)
git log --all --pretty=format: --name-only | sort -u | sed '/^$/d'

# 中文文件名会被转义,用 core.quotepath=false 输出真实路径
git -c core.quotepath=false log --all --pretty=format: --name-only | sort -u | sed '/^$/d'

# 扫敏感文件:.env/密钥/证书后缀、.db,以及路径含 secret/credential/token 的文件
git log --all --pretty=format: --name-only | sort -u | \
  grep -iE "\.(env|key|pem|p12|pfx|crt|cer)$|secret|credential|token|\.db$"

# 真实 .env 是否曾被提交(有输出即曾有 commit 触及 .env)
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

**注意 squash merge 陷阱**:走 squash merge 的分支,`--is-ancestor` 会显示「未合并」,但内容已进 main。判断依据看 commit message 是否带 PR 编号(`(#6)`),或看分支 tree 是否还是旧状态(如仍含 `.envrc`)。这类分支可安全删。

### 4. 制定历史清除清单

把待清除路径写成清单文件,供 filter-repo 使用。每个路径必须满足:**当前 main 已不存在**(否则会误删当前文件)。

```bash
# 核对清单路径在当前 main 是否存在(必须全部「仅历史有」)
for p in <路径>; do
  [ -n "$(git ls-files "$p" | head -1)" ] && echo "⚠️ 当前main仍有: $p" || echo "✅ 仅历史: $p"
done
```

典型该清的类别:

- 个人配置:`.claude/` `.zed/` `.hindsight/` `.mcp.json` `.opencode/` `.beads/`
- 开发过程产物:`.planning/` `PLAN.md` `TODO.md` 临时 todos
- 已迁移的旧环境:`flake.nix` `flake.lock` `.envrc`
- v1 旧结构:`actions/`(根级)、根级散落 `.py`(已重构进 `src/` 的)
- 不开源的内部文档:`docs/plans/` `docs/needs/` `docs/superpowers/`

**根级 .py 陷阱**:`git log --all --name-only | grep "config.py"` 这类模糊匹配会命中 `src/.../config.py`,误以为没清干净。验证用精确前缀 `grep -E "^${path}"`;清单里写根级路径前,先确认它在历史中确实存在于根级(`git log --all --name-only | grep "^config.py$"`,0 条则历史本就没有,从清单移除)。

**子目录同名文件**:`flake.nix` 在根级和 `sub-dir/flake.nix` 是两个路径。清单写 `flake.nix` 是根级精确匹配,不会误清子目录;要清子目录的,单独写 `sub-dir/flake.nix`。

### 5. filter-repo 副本实验(必须先做)

直接在主仓跑 filter-repo 不可逆。先 clone 副本验证。

```bash
# clone 副本(--no-local 走完整传输)
git clone --no-local <主仓> /tmp/<project>-rewrite-test
cd /tmp/<project>-rewrite-test

# 关键:--invert-paths 表示「排除」清单路径;漏写则变成「只保留」清单路径,删光其余文件
git filter-repo --invert-paths --paths-from-file /tmp/cleanup_paths.txt --force

# 切回 main 并重置工作区(filter-repo 结束时已执行 git reset --hard,这里确保停在 main)
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

# 执行(记录 origin 原地址备用)
git filter-repo --invert-paths --paths-from-file /tmp/cleanup_paths.txt --force

# 切回 main 并重置工作区
git checkout main
git reset --hard HEAD

# 重连 origin
git remote add origin https://github.com/<user>/<project>.git
```

filter-repo 会移除 origin remote,这是它的设计行为(防止误推回原仓),所以 rewrite 后要手动重连。

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

rewrite 后本地还留着大量旧历史分支(含被清除的文件),已全部归档到 archive 仓,可删。删之前先排查 worktree 关联分支。

```bash
# 查 worktree 关联的分支(这些要先处理 worktree)
git worktree list

# 失效 worktree 目录残留 + 关联,prune 清理
git worktree prune
rm -rf .worktrees/<失效目录>

# 删除非保留分支(排除 main 和 worktree 分支)
git branch | sed 's/^[* +]*//' | grep -vE '^(main|<worktree分支>)$' | xargs -I{} git branch -D {}

# 可选:移除 archive remote 及其 refs/remotes/archive/*(已被 filter-repo 重写,不再对应归档仓的原始历史,旧历史请到归档仓查阅)
git remote remove archive
```

`git branch -D` 报错是因为分支被 worktree checkout。先 `git worktree prune`(目录已失效时)或 `git worktree remove`(目录还在时),再删分支。
