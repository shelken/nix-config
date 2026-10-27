---
name: verify-sandbox
description: 验证 nix-config 的 Agent 沙箱（sb、omp-sb、sb sync、launcher、sb.yaml、.sandbox.yaml）行为时使用：在一次性 MSB_HOME 中用当前分支真实构建的 sb 启动主 VM，按功能地图驱动并留存证据，不碰日常 VM
---

# Agent 沙箱真实验证

用户接触的 surface 是宿主 CLI：`omp-sb`、`sb run`、`sb shell`、`sb sync`、`sb status`、`sb up/down/rm`，以及两份配置 `sb.yaml`（能力上限）和项目 `.sandbox.yaml`（能力授权）。机制见 [沙箱 README](../../../modules/features/ai/sandbox/README.md)，用户视角见 [用户指南](../../../docs/user-guide/03-agent-sandbox.md)

先读 [`features/README.md`](features/README.md)，按改动影响选所有对应 feature；一个方便入口通过不代表 map 里其他入口也通过

所有操作经 [`scripts/verify.sh`](scripts/verify.sh)。它把 `SB_CONFIG`、`SB_SANDBOX_CONFIG`、`MSB_HOME`、`MSB_CONFIG_PATH` 一起指向隔离目录，日常主 VM（`~/Data/sandboxes/msb` 里的 `sb-main`）与宿主 `~/.config/sandbox` 不受影响。并行跑两套时用不同的 `SB_VERIFY_RUN`

## Launch

```bash
V="$(git rev-parse --show-toplevel)/.agents/skills/verify-sandbox/scripts/verify.sh"   # 必须是绝对路径：run 会切到测试项目执行
eval "$($V env)" # MODEL、GATEWAY_URL、GATEWAY_ADDR、CPUS、MEMORY：从仓库事实源现算，文档不写死
$V setup          # 构建当前分支的 Home Manager 产物（主机由 SB_VERIFY_HOST 选）、发布隔离配置、建测试项目
$V doctor
$V sb up          # 首次创建数据卷与主 VM，并自动 sb sync 一次
$V sb status      # 就绪：VM 状态 Running、上限一致 consistent、缺失工具 无
```

- `setup` 需要 Linux 构建器（本机 `linux-builder` VM 已启动）
- 主 VM 规格：`$CPUS` 照抄仓库 `sb.yaml`，`$MEMORY` 为验证用的较小值，用 `SB_VERIFY_MEMORY` 覆盖；其他字段照抄 `sb.yaml`
- 首次 `sb up` 要装插件（`bun install`），耗时取决于网络；mise 工具来自宿主共用层，已装齐时不下载

## Doctor

```bash
$V doctor
```

检查 msb 版本、`sec-run`、共用 mise 目录、构建产物与 GC root、隔离配置已发布、测试项目、msb 配置的 `home` 指向隔离目录、Linux 构建器。任何一项失败即停止，先修前置条件。行为异常时先跑它

## Drive

- 沙箱 CLI：`$V sb <子命令>`，工作目录固定为测试项目 `$HOME/Code/sb-verify-<RUN>`
- guest 内直接检查（绕过上下文，看 VM 本身）：`$V msb exec sb-main -- <命令>`
- 路径：`$V paths`
- 功能步骤见 `features/` 下各文件

调用 OMP 一律用 `$MODEL`：`$V sb run omp --model="$MODEL" -p '只回复 OK'`，并给命令加超时（`timeout 120`）

## Evidence

```bash
$V run <名字> -- $V sb run uname -m
```

在 `/private/tmp/sb-verify/<RUN>/evidence/` 写 `<名字>.cmd/.out/.err/.rc`（`/tmp` 重启后清空，需要长期保留的证据自行拷走）。证明标准：

- 走用户路径（`sb`、`omp-sb`），不手改 guest 内状态冒充结果；`msb exec` 只用于读取旁证
- 同时记录动作与结果状态，例如改 `sb.yaml` 前后各一份 `sb status`
- 验证副作用：共用 mise 目录大小（`du -sk ~/Data/sandboxes/mise/aarch64-linux`）、guest 内文件、宿主 git 提交
- 后台启动的上下文必须保留输出，否则无法区分「没启动」和「行为错误」

## Cleanup

```bash
$V cleanup
```

只经隔离 `MSB_HOME` 删除本次创建的 VM 与卷，删除工作目录与测试项目，保留 evidence 目录。不要按进程名 kill：日常主 VM 同样叫 `sb-main`。每次失败的迭代后也执行

## 未覆盖的部分

隔离环境替代了真实 `just hm` 激活，以下步骤在这里不执行，只能在授权的 `just hm` 后观察：

- 激活脚本把配置发布到宿主 `~/.config/sandbox/current`，以及创建共用 mise 目录
- `SB_MISE_HOST_DIR`、`MSB_HOME`、`MSB_CONFIG_PATH` 由 Home Manager 会话变量注入，需新开终端生效
- 日常 `sb-main` 使用 `~/Data/sandboxes/msb`；隔离环境里的 VM 同样叫 `sb-main`，只能靠 `MSB_HOME` 区分

## Gotchas

- `sb sync` 写宿主真实共用 mise 层（设计如此，只补缺）。验证中不要 `mise use -g` 引入新工具再 sync，除非任务需要
- 家里的模型服务在 `$GATEWAY_ADDR`，靠 `sb.yaml` 的 `network.default_grant` 放行；用 IP 直连会因缺 SNI 失败，测试用 `$GATEWAY_URL` 的域名
- Determinate 的 Native Linux Builder 不可用时，`setup` 构建失败，见 `postmortems/004-*`
