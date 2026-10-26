# 工具补齐

`sb sync` 把登记的 mise 工具和 OMP 插件补齐到沙箱，只补缺，多个 sync 同时执行时排队；Agent 在上下文里不能自己装工具

## Sub-features

- `sync-noop` 工具已齐时不下载，共用层大小不变
- `sync-serial` 两个 sync 同时启动时串行完成，都成功
- `sync-tty` 在真实终端里 `sb sync` 能执行（msb 的 `--stream` 在 stdin 是终端时报错）；stdin 是终端、stdout 被管道时 `sb run` 也能执行
- `sync-private` 私有插件经 `GITHUB_TOKEN` clone 安装
- `sync-tools` 登记的 Nix 与 mise 工具在上下文内可用
- `ctx-no-install` 上下文内 `mise use -g` 失败且不写配置
- `ctx-offline` 上下文内 mise 不联网：项目 `mise.toml` 写 `latest` 的大版本列表工具不再超时拖慢启动，OMP 仍能正常调用模型

## How to get to it (user POV)

- 宿主运行 `sb sync`
- 新建主 VM 时自动执行一次

## Driving it with verify.sh

Preconditions:

- 首次启动已完成

- **重复 sync。** 取 `du -sk ~/Data/sandboxes/mise/aarch64-linux`，运行 `$V run sync1 -- $V sb sync & $V run sync2 -- $V sb sync & wait`，再取一次 `du`。两份 stderr 或 stdout 含「所有 mise 工具均已安装，本次不发起任何安装」，两个 `rc` 为 `0`，两次 `du` 相同
- **终端里 sync。** `$V run` 的 stdin 不是终端，测不到这一项，要用 `script` 分配 pty：`script -q /dev/null $V sb sync`，退出码为 `0`，输出含「工具与插件补齐成功」，不含「`--stream` requires piped stdin」。再运行 `script -q /dev/null bash -c "$V sb run echo hi | cat"`，输出含 `hi`，不含同一报错
- **工具可用。** 运行 `$V run tools -- $V sb run bash -c 'for c in rg fd jq gh node python3 uv omp pi codex claude bun mise git; do printf "%s " $c; $c --version 2>&1 | head -1; done'`。每行都有版本号，没有空行
- **私有插件。** 运行 `$V msb exec sb-main -- bash -c 'cd /data/xdg/data/omp/plugins/node_modules && find -L pi-trae-provider pi-zed-provider -type f | wc -l'`。数量远大于 0（实测 125 与 5752 个文件）
- **上下文内不能装工具。** 运行 `$V run ctx-install -- $V sb run bash -c 'mise use -g yq@4.44.3; echo rc=$?; cat /data/mise/config.toml'`。输出含 `Read-only file system` 与 `rc=1`，配置文件不存在
- **上下文内 mise 不联网。** 在测试项目写 `mise.toml`：`[tools]` 下 `mc = "latest"`，运行 `$V run ctx-offline -- $V sb run env MISE_TRUSTED_CONFIG_PATHS="$PROJ" omp --model=cpa/gpt-5.6-luna -p '只回复 OK'`。`rc` 为 `0`，stdout 为 `OK`，stderr 不含「timed out」；对照旧行为每次多花 4 到 5 秒并刷两行超时警告。结束后删除 `mise.toml`

## Gotchas

- `sb sync` 写真实共用层；不要为了测试引入新工具
- 私有插件 clone 失败只打警告且 `rc` 仍为 `0`，必须看插件目录内容
- guest 里的插件 `package.json` 把私有依赖改写为 `file:/data/xdg/data/omp/plugins/.git-vendor/…`，这是设计
- 验证终端行为时必须用 `script -q /dev/null <命令>` 分配 pty；直接 `$V run` 或管道调用的 stdin 不是终端，这类 bug 测不出来
