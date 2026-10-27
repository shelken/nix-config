# OMP 与 pi 调用模型

用户在沙箱里运行 OMP 或 pi，它们能写自己的数据库、发现家里模型服务上的模型，并完成一次对话

## Sub-features

- `omp-db` OMP 数据库建在 `/data/xdg/data/omp`，不写 `~/.omp/agent`
- `omp-discovery` `models.yml` 里声明了 `discovery` 的 provider 出现在模型列表：私网域名的（`cpa`、`commandcode-local`）一定出现，走宿主端口的（如 `mp`）只在宿主服务在跑时出现
- `omp-chat` 用便宜模型完成一次单轮对话
- `omp-no-project-grant` 项目不写 `.sandbox.yaml` 也能访问模型服务
- `pi-packages` pi 首次启动自己装齐 `settings.json` 的 packages，`node-pty` 在 guest 里现场编译，不报 `node-gyp` 缺失；之后启动不再安装
- `pi-chat` 发现缓存为空时，`pi -p --model <动态模型>` 第一次就能解析并完成一次单轮对话

## How to get to it (user POV)

- `omp-sb --model=<模型> -p '<提示>'`
- `omp-sb` 交互会话
- `sb run omp …`
- `sb run pi …`

## Driving it with verify.sh

Preconditions:

- 首次启动已完成，测试项目没有 `.sandbox.yaml`

- **列出 provider。** 运行 `$V run providers -- $V sb run bash -c 'omp models | grep -E "^[a-z].*\([0-9]+\)$"'`。输出含 `cpa`、`commandcode-local`，宿主服务在跑时还含 `mp`
- **单轮对话。** 运行 `$V run chat -- timeout 120 $V sb run omp --model="$MODEL" -p '只回复两个字母：OK'`。`chat.out` 含 `OK`，`chat.rc` 为 `0`
- **数据库位置。** 运行 `$V msb exec sb-main -- ls /data/xdg/data/omp`。列出 `agent.db`、`models.db`
- **pi 首启装包与冷缓存对话。** 清空运行状态：`$V msb exec sb-main -- rm -rf /data/home/.pi/agent/npm /data/home/.pi/agent/git /data/home/.pi/agent/cache`。运行 `$V run pi-first -- timeout 300 $V sb run pi --model "$MODEL" -p '只回复 OK'`。`pi-first.out` 含 `OK`，`rc` 为 `0`，`pi-first.err`（装包进度走 stderr）含 `package installed`，两个文件都不含 `node-gyp`。确认现场编译成功：`$V msb exec sb-main -- find /data/home/.pi/agent/git -path '*node-pty/build/Release/pty.node'` 输出一行
- **pi 对话。** 运行 `$V run pi-chat -- timeout 150 $V sb run pi --model "$MODEL" -p '只回复 OK'`。`pi-chat.out` 含 `OK`，`rc` 为 `0`，stderr 没有装包进度
- **并发首启。** 新数据卷上同时启动多个 pi，只有一部分成功，其余报 `Model "…" not found`；装完之后同时启动多个全部成功，没有查根因。验证并发时先单独首启一次，再并发

## Gotchas

- 不指定 `--model` 会用默认模型，计费更高；默认模型不可达时 OMP 反复重试看起来像卡住，用 `timeout`
- 模型列表只剩 `anthropic`、`commandcode`、`wx` 时，查 `/data/xdg/state/omp/logs/omp.*.log` 里的 `model discovery failed`
- `SQLITE_CANTOPEN … /root/.omp/agent/agent.db` 表示 `/data/xdg/data/omp` 不存在
- 调 pi 不要用 `anthropic/` 模型
