# Refactor closure diff

Refactor closure diff 用于移动文件、调整模块结构、改写 helper 这类「不应改变行为」的变更：对比两个修订下某台主机的系统与 Home derivation 闭包，证明结果只差 store hash 与列表顺序。它只求值，不构建、不切换，也能覆盖本机之外的主机

## Sub-features

- `closure-diff-added-removed` 按名字列出新增或删除的 derivation
- `closure-diff-hash-only` 把 store hash 替换为占位符后完全相同的 derivation 只计数
- `closure-diff-order-only` 排序后相同、只有列表或行顺序不同的 derivation
- `closure-diff-real` 排序后仍不同的 derivation，即实际内容差异
- `closure-diff-collisions` `ignoreCollisions = true` 的 buildEnv 中，各包首次出现顺序发生变化的 derivation

## How to get to it (user POV)

- 在仓库根目录运行 `.agents/skills/verify-nix-config/scripts/closure-diff.py <before-rev> <host>`，`<before-rev>` 是变更前的修订，工作树作为变更后
- 第三个参数可指定变更后的 flake ref，例如另一个 worktree 的路径

## Driving it with Bash

Preconditions:

- 新增或删除的文件已 `git add`：flake 在 git ref 下看到暂存的新增与暂存的删除，但未暂存的删除会直接报 `Path '…' does not exist in Git repository`，未跟踪文件不可见
- `<host>` 是 `darwinConfigurations` 或 `nixosConfigurations` 中的名字；`homeConfigurations` 对每台主机都会生成，不需要额外条件

- **逐台运行。** 对每台受影响主机执行一次，按顺序跑；每次要完整求值两个修订，多台并行会占满 CPU
  ```bash
  for h in mio yuuko; do .agents/skills/verify-nix-config/scripts/closure-diff.py <before-rev> "$h"; done
  ```
- **读结果。** 每台主机输出 `sys` 和 `home` 两行 JSON。行为不变的判据是 `added`、`removed`、`real`、`collisions` 全空。脚本在求值失败时输出 `EVAL ERROR` 但退出码仍为 `0`，所以不能只看退出码；两行都必须是 JSON 而不是 `EVAL ERROR`。把变更对象本身当基线（`<before-rev>` 取工作树的修订）得到全空，是确认脚本本身可用的最快办法
- **解释 `real`。** 仓库内文件被移动时，`mkConfigFile` 的 liveEdit 软链目标路径会变，表现为 `hm_*.drv` 出现在 `real`。用 `nix derivation show -r` 取出两侧 derivation，把旧、新路径前缀替换成同一个字符串后重新比较，归零才算路径前缀变化
- **解释 `orderOnly`。** 它按空白切词后比较多重集，所以只调整词序的变化也会落在这里；同一构建脚本里命令的先后顺序被调换时，它仍会被判为等价。`collisions` 只在 `orderOnly` 的 derivation 里检查带 `ignoreCollisions` 的 buildEnv 的首次出现顺序；已落在 `real` 或 `hashOnly` 的不会被检查。看到 `orderOnly` 要人工读一遍对应 derivation，不要当作无影响

## Gotchas

- 求值失败的一侧输出 `EVAL ERROR` 且退出码为 `0`；先确认基线本身能否求值，再归因到本次变更
- `added`/`removed` 按去掉 hash 的名字比较，同名 derivation 的版本变化会落在 `real`
- `mkConfigFile` 的软链目标在 `liveEdit = true` 的主机上是仓库工作区路径，移动文件才会让 `hm_*.drv` 进入 `real`；`liveEdit = false` 的主机取 `modules/` 快照，`modules/` 内任一文件变化都会改变快照 hash，让引用它的 `hm_*.drv` 进入 `real`。验证前缀替换时，路径在 derivation 的 `env.buildCommand` 里
- 只证明 derivation 层面等价；Homebrew 实际安装、launchd 运行状态等副作用仍需 build 或 switch 验证
