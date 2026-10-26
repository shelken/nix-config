# OMP 与 pi 调用模型

用户在沙箱里运行 OMP 或 pi，它们能写自己的数据库、发现家里模型服务上的模型，并完成一次对话

## Sub-features

- `omp-db` OMP 数据库建在 `/data/xdg/data/omp`，不写 `~/.omp/agent`
- `omp-discovery` 私网模型服务的 provider（cpa、commandcode-local、mp）出现在模型列表
- `omp-chat` 用便宜模型完成一次单轮对话
- `omp-no-project-grant` 项目不写 `.sandbox.yaml` 也能访问模型服务
- `pi-packages` pi 首次启动自己装齐 `settings.json` 的 packages，跳过安装脚本，不需要 `node-gyp`；之后启动不再安装
- `pi-chat` 模型发现缓存预热后，`pi -p` 用便宜模型完成一次单轮对话

## How to get to it (user POV)

- `omp-sb --model=<模型> -p '<提示>'`
- `omp-sb` 交互会话
- `sb run omp …`
- `sb run pi …`

## Driving it with verify.sh

Preconditions:

- 首次启动已完成，测试项目没有 `.sandbox.yaml`

- **列出 provider。** 运行 `$V run providers -- $V sb run bash -c 'omp models | grep -E "^[a-z].*\([0-9]+\)$"'`。输出含 `cpa`、`commandcode-local`、`mp`
- **单轮对话。** 运行 `$V run chat -- timeout 120 $V sb run omp --model=cpa/gpt-5.6-luna -p '只回复两个字母：OK'`。`chat.out` 含 `OK`，`chat.rc` 为 `0`，耗时十几秒
- **数据库位置。** 运行 `$V msb exec sb-main -- ls /data/xdg/data/omp`。列出 `agent.db`、`models.db`
- **pi 首启装包。** 清空运行状态：`$V msb exec sb-main -- rm -rf /data/home/.pi/agent/npm /data/home/.pi/agent/git /data/home/.pi/agent/cache`。运行 `$V run pi-first -- timeout 300 $V sb run pi --model cpa/workbuddy/deepseek-v4.1-flash -p '只回复 OK'`。`pi-first.err`（装包进度走 stderr）含 `package installed`，两个文件都不含 `node-gyp`，耗时约 50 秒；冷缓存下 `pi-first.err` 末尾报 `Model "cpa/…" not found`、`rc` 为 `1`，这是预期。确认安装脚本被跳过：`$V msb exec sb-main -- ls /data/home/.pi/agent/git/github.com/shelken/pi-extensions/node_modules/.bun/node-pty@1.1.0/node_modules/node-pty/build` 报不存在
- **pi 预热模型发现。** 运行 `$V run pi-warm -- timeout 150 $V sb run pi -p '只回复 OK'`，不带 `--model`：会话开始即写缓存，pi 回退到未登录的 `zed` 模型，输出 `Zed 未登录`、`rc` 为 `1`，这是预期。之后 `$V sb run ls /root/.pi/agent/cache/provider-models` 列出 `cpa.json`、`mp.json`。预热步骤偶发跑满超时（根因未查，见 README）：见过的那一次 `rc` 为 `124`，缓存已写好，所以先看目录再决定是否重跑
- **pi 对话。** 运行 `$V run pi-chat -- timeout 150 $V sb run pi --model cpa/workbuddy/deepseek-v4.1-flash -p '只回复 OK'`。`pi-chat.out` 含 `OK`，`rc` 为 `0`，十几秒内完成，不再安装
- **不验证并发首启。** 同时首启多个 pi 可能失败，根因未查，这里没有可靠的通过判据；新数据卷上先单独跑一次「pi 首启装包」再并发

## Gotchas

- 不指定 `--model` 会用默认模型，计费更高；默认模型不可达时 OMP 反复重试看起来像卡住，用 `timeout`
- 模型列表只剩 `anthropic`、`commandcode`、`wx` 时，查 `/data/xdg/state/omp/logs/omp.*.log` 里的 `model discovery failed`
- `SQLITE_CANTOPEN … /root/.omp/agent/agent.db` 表示 `/data/xdg/data/omp` 不存在
- pi 的 cpa、mp 等 provider 的模型来自 `pi-dynamic-models` 的自动发现，发现发生在会话开始之后，晚于 `-p` 解析 `--model`。显式 `--model cpa/…` 的 `-p` 失败在会话开始之前，不会写缓存，必须先按「pi 预热模型发现」不带 `--model` 跑一次
- 调 pi 不要用 `anthropic/` 模型
