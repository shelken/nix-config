# OMP 调用模型

用户在沙箱里运行 OMP，OMP 能写自己的数据库、发现家里模型服务上的模型，并完成一次对话

## Sub-features

- `omp-db` OMP 数据库建在 `/data/xdg/data/omp`，不写 `~/.omp/agent`
- `omp-discovery` 私网模型服务的 provider（cpa、commandcode-local、mp）出现在模型列表
- `omp-chat` 用便宜模型完成一次单轮对话
- `omp-no-project-grant` 项目不写 `.sandbox.yaml` 也能访问模型服务

## How to get to it (user POV)

- `omp-sb --model=<模型> -p '<提示>'`
- `omp-sb` 交互会话
- `sb run omp …`

## Driving it with verify.sh

Preconditions:

- 首次启动已完成，测试项目没有 `.sandbox.yaml`

- **列出 provider。** 运行 `$V run providers -- $V sb run bash -c 'omp models | grep -E "^[a-z].*\([0-9]+\)$"'`。输出含 `cpa`、`commandcode-local`、`mp`
- **单轮对话。** 运行 `$V run chat -- timeout 120 $V sb run omp --model=cpa/gpt-5.6-luna -p '只回复两个字母：OK'`。`chat.out` 含 `OK`，`chat.rc` 为 `0`，耗时十几秒
- **数据库位置。** 运行 `$V msb exec sb-main -- ls /data/xdg/data/omp`。列出 `agent.db`、`models.db`

## Gotchas

- 不指定 `--model` 会用默认模型，计费更高；默认模型不可达时 OMP 反复重试看起来像卡住，用 `timeout`
- 模型列表只剩 `anthropic`、`commandcode`、`wx` 时，查 `/data/xdg/state/omp/logs/omp.*.log` 里的 `model discovery failed`
- `SQLITE_CANTOPEN … /root/.omp/agent/agent.db` 表示 `/data/xdg/data/omp` 不存在
