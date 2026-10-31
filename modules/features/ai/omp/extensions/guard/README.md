# guard

omp 工具调用拦截扩展。权限文件的写法见 `modules/features/ai/omp/README.md`「Guard 权限」

## 定位

- 拦截配合的 agent 手滑：误删大范围目录、误读凭据、执行未落盘的下载脚本
- 不防对抗性绕过：`bun -e 'readFileSync(".env")'` 这类解释器内读取不在范围内，隔离交给 sb 沙箱
- 误伤按缺陷处理：拦截只落在真实危险目标上，规则变更用会话重放衡量误伤
- 内置规则只放通用安全项；个人操作规范（全仓暂存、硬 reset、全盘 `find`）写在全局权限文件，拒绝理由给出替代做法

## 内置规则

| 类别 | 拦截 | 放行 |
|---|---|---|
| 递归强制删除 | `rm -rf` 目标为 `/`、`~`、`.`、`..` 或它们下的全量通配；变量按空串处理，`$d/*` 视为 `/*` | 定向路径、`/tmp/x-*`、`"$d"` |
| 下载执行 | `curl` / `wget` 同一管道下游的 shell 或解释器从 stdin 读取程序 | 解释器带 `-c` / `-e` 脚本或脚本文件参数 |
| 环境变量全量读取 | `env`、`printenv`、`export -p`，含 `env \| grep` | `printenv NAME`、`echo $NAME` |
| 裸设备 | `dd of=/dev/*`、`mkfs*` | |
| 凭据路径 | `~/.ssh/*`、`~/.aws`、`~/.gnupg`、`~/.config/sops/age`、`~/.netrc` 等、shell 历史 | `~/.ssh` 下的 `config`、`known_hosts*`、`*.pub` |
| 环境文件 | `.env`、`.env.*`（含 cwd 之外的同名文件） | `.tpl`、`.example`、`.sample`、`.template` 后缀 |

- 内置路径例外只用于内置规则，权限文件不提供放行语法；项目需要收紧时追加拒绝规则，例如 `**/.env.tpl`
- 路径先解析软链接再匹配，指向 `.env` 的 `.env.tpl` 链接按 `.env` 拦截
- `ls`、`stat`、`test`、`[`、`[[`、`echo`、`printf`、`git check-ignore` 只涉及元数据或字面回显，不算读取；`ls` 的操作数与通配不限，接了管道就不豁免（下游可能真的读内容），重定向目标照旧参与判定

## Bash 判定

- 词法拆分 `;`、`|`、`&&`、`||`、子 shell 与换行，递归检查 `$()`、反引号、`sh -c`、`eval`，以及管道里被 shell 当程序执行的 heredoc 正文（python 之类的 heredoc 是另一种语言，不按 shell 判定）
- 剥离 `sudo`、`env`、`timeout`、`nohup`、`time` 等包装器与前置变量赋值后匹配命令规则
- 含 `/` 或以 `.env` 开头的词按路径规则匹配，重定向目标同样参与
- 命令规则按词前缀匹配，`find ~` 只命中家目录本身，`find ~/Code` 不受影响；`git add -A` / `git add .` 只看暂存参数是否为全量范围

## 模块结构

omp 加载 `extensions/<名>/index.ts`，Home Manager 软链整个目录，目录内其余文件不会被当作扩展加载

- `index.ts`：唯一判定入口 `evaluateGuard(call, policy)` 与 omp 扩展注册
- `shell.ts`：词法与命令拆分，输出带引用、通配、动态展开标记的词
- `policy.ts`：读取权限文件、叠加层级，加载时把路径规则编译为绝对 glob
- `guard.test.ts`：只经 `evaluateGuard` 测试，用例取自误伤重放的真实样本
- `replay.ts`：误伤重放

## 误伤重放

重放 `~/.omp/agent/sessions` 中所有曾被拦截的调用，按规则统计指定 guard 版本下仍拦截的次数；`--samples` 列出某条规则的命中命令。用户规则取自部署中的权限文件，比对尚未部署的版本时用 `OMP_AGENT_DIR` 指向另一份权限文件所在目录

```bash
git show main:modules/features/ai/omp/extensions/guard.ts > /tmp/guard-main.ts
bun modules/features/ai/omp/extensions/guard/replay.ts /tmp/guard-main.ts
bun modules/features/ai/omp/extensions/guard/replay.ts modules/features/ai/omp/extensions/guard/index.ts --samples "rm -rf *"
OMP_AGENT_DIR=/tmp/agent-new bun modules/features/ai/omp/extensions/guard/replay.ts modules/features/ai/omp/extensions/guard/index.ts
```
