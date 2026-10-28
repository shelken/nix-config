# 工具补齐

`sb sync` 把登记的 mise 工具和 OMP 插件补齐到沙箱，多个 sync 同时执行时排队（上限 600 秒，超时非零退出）。mise 工具只补缺；OMP 插件每次按清单重建，恢复缺失插件，删除清单外插件和旧登记表，保留下载缓存。Agent 在上下文里不能自己装工具。

## Sub-features

- `sync-noop` 工具已齐时 mise 不再下载，OMP 插件仍使用保留的锁文件和缓存重建
- `sync-serial` 两个 sync 同时启动时串行完成，都成功
- `sync-tty` 在真实终端里 `sb sync` 能执行（msb 的 `--stream` 在 stdin 是终端时报错，文案为 `--stream requires piped stdin or --no-stdin`）；stdin 是终端、stdout 被管道时 `sb run` 也能执行
- `sync-private` 私有插件经 bun 安装，GitHub 凭据来自 `GITHUB_TOKEN` 占位符
- `sync-repair` 清单未变时仍恢复缺失插件，删除额外插件和旧登记表
- `sync-tools` 登记的 Nix 与 mise 工具在上下文内可用
- `ctx-no-install` 上下文内 `mise use -g` 失败且不写配置
- `ctx-offline` 上下文内 `MISE_OFFLINE=1`：项目 `mise.toml` 写 `latest` 的大版本列表工具不会因联网查询拖慢启动，OMP 仍能正常调用模型

## How to get to it (user POV)

- 宿主运行 `sb sync`
- 新建主 VM 时自动执行一次；VM 重建（上限变化）和复用已有 VM 都不执行

## Driving it with verify.sh

Preconditions:

- 首次启动已完成
- 共用层目录 `M=${SB_MISE_HOST_DIR:-$HOME/Data/sandboxes/mise/aarch64-linux}`（默认值写在 `sb.sh` 里），harness 不隔离它，下面的 `sb sync` 写的是真实共用层

- **重复 sync。** 运行 `$V run sync1 -- $V sb sync & $V run sync2 -- $V sb sync & wait`。`sync1.rc` 与 `sync2.rc` 都是 `0`，两份 `.out` 或 `.err` 含「工具与插件补齐成功」。mise 不重复下载已安装工具，Bun 缓存目录保留；插件重建会更新文件，不以两次 `du` 相等作为判据
- **恢复插件。** 运行 `$V msb exec sb-main -- bash -c 'p=/data/xdg/data/omp/plugins; rm -rf "$p/node_modules/pi-trae-provider"; mkdir -p "$p/node_modules/hand-installed"; printf "{}\n" > "$p/omp-plugins.lock.json"'`，再运行 `$V run sync-repair -- $V sb sync`。`sync-repair.rc` 为 `0`。运行 `$V msb exec sb-main -- bash -c 'p=/data/xdg/data/omp/plugins; test -d "$p/node_modules/pi-trae-provider" && test ! -e "$p/node_modules/hand-installed" && test ! -e "$p/omp-plugins.lock.json"'`，退出码为 `0`。本项在测试 VM 的数据卷中执行，不修改共用下载缓存
- **终端里 sync。** `$V run` 的 stdin 不是终端，测不到这一项，要用 `script` 分配 pty：`script -q /dev/null $V sb sync`，退出码为 `0`，输出含「工具与插件补齐成功」，不含「`--stream` requires piped stdin」。再运行 `script -q /dev/null bash -c "$V sb run echo hi | cat"`，输出含 `hi`，不含同一报错
- **工具可用。** 运行 `$V run tools -- $V sb run bash -c 'for c in rg fd jq gh node python3 uv omp pi codex claude bun mise git; do echo "$c: $($c --version 2>&1 | head -1)"; done'`。`tools.out` 恰好 14 行，每行 `<名字>: ` 之后是版本号，没有 `not found`。这份名单是 mise 登记表加基础工具的子集，增删登记项时同步检查
- **私有插件。** 运行 `$V msb exec sb-main -- bash -c 'cd /data/xdg/data/omp/plugins/node_modules && for p in pi-trae-provider pi-zed-provider; do echo "$p $(find -L $p -type f | wc -l)"; done'`。两个数字都大于 0（实测 125 与 60）。`$V msb exec sb-main -- bash -c '. /run/sandbox-config/current/guest-env.sh; omp plugin doctor'` 里这两个插件前面是 ✔，汇总行是 `0 errors`
- **上下文内不能装工具。** 运行 `$V run ctx-install -- $V sb run bash -c 'mise use -g yq@4.44.3 2>&1; echo rc=$?; ls /data/mise/config.toml 2>&1'`。`.out` 含 `Read-only file system`（只读的是共用层 `/opt/sandbox-mise`）、命令自己回显的 `rc=1`，`/data/mise/config.toml` 不存在；`ctx-install.rc` 是最后一条 `ls` 的退出码，不作判据
- **上下文内 mise 不联网。** 运行 `$V run offline-flag -- $V sb run bash -c 'echo MISE_OFFLINE=$MISE_OFFLINE'`，`.out` 为 `MISE_OFFLINE=1`。再在测试项目写 `mise.toml`：`[tools]` 下 `mc = "latest"`，运行 `$V run ctx-offline -- $V sb run env MISE_TRUSTED_CONFIG_PATHS="$PROJ" omp --model="$MODEL" -p '只回复 OK'`。`ctx-offline.rc` 为 `0`，`.out` 为 `OK`，`.out` 与 `.err` 都不含「timed out」。结束后删除 `mise.toml`

## Gotchas

- `sb sync` 写真实共用层；不要为了测试引入新工具
- 私有插件装不上时 `sb sync` 的 `rc` 非零（宿主上 `SB_POSTINSTALL_STRICT=1` 直接 `exit 1`）。bun 对私有 git 依赖会先打几行 `Authentication failed`，再通过 `gh auth git-credential` 重试；最终 `rc` 为 `0` 且插件目录有内容时可忽略这些行
- 验证终端行为时必须用 `script -q /dev/null <命令>` 分配 pty；直接 `$V run` 或管道调用的 stdin 不是终端，这类 bug 测不出来
