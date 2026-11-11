# agent-gh

让 agent 在用户自己的仓库里发 issue 和评论时，使用 agent 专属的 GitHub 身份，而不是用户本人的身份

`bin/gh` 与真实 `gh` 接口相同。调用命中「规则表」且目标仓库的 owner 是 `vars.username` 时，设置 `GH_TOKEN=$AGENT_GITHUB_TOKEN` 再交给真实 `gh`；其余调用原样交给真实 `gh`

## 规则

规则表是 [agent-gh.sh](./agent-gh.sh) 开头的 `rules`：命中判断与缺 token 时的报错清单共用这一份，当前是 `issue create`、`issue new`、`issue comment`、`pr comment`

- 目标仓库的 owner 按 `gh` 自己的优先级判断：issue 或 PR 链接 > `-R`/`--repo` > `GH_REPO` > 当前目录。当前目录交给 `gh repo view` 解析，只在命中规则表时才会调用
- 命中但 `AGENT_GITHUB_TOKEN` 缺失或为空：直接失败并列出必须使用 agent token 的操作，不退回用户身份
- owner 不是用户、或 owner 解析不出来：原样交给真实 `gh`，由它自己决定成败

## 接线

| 位置 | 作法 |
| --- | --- |
| 密钥 | [secrets.nix](../../secrets/secrets.nix) 的 `secretEnvMap` 把 sops 的 `github/agent-token` 导出成 `AGENT_GITHUB_TOKEN`，经 `sec-run` 进入 omp、pi 的环境 |
| 宿主 | [_launch.nix](./_launch.nix) 生成 omp、pi 的启动别名：在 `sec-run` 前把包装目录放到 `PATH` 最前。不放全局 `PATH`，否则用户自己用 `gh` 的身份也会变 |
| 沙箱 | [sb.yaml](../sandbox/sb.yaml) 声明 secret `AGENT_GITHUB_TOKEN`；[_guest.nix](../sandbox/_guest.nix) 用 `linuxPkgs` 构建同一个包装，放到 guest PATH 最前面。整台 VM 都是 agent 环境，不区分身份 |
| 构建 | [_package.nix](./_package.nix) 用 `writeShellApplication`，`runtimeInputs` 让脚本里的 `gh` 解析到真实 `gh` |

沙箱里 guest 只有占位符，msb 发往 `github.com`、`api.github.com` 的请求时才换成真实值。创建或启动 VM 时 msb 必须拿到 `AGENT_GITHUB_TOKEN`，缺失时拒绝创建；`sb` 在这两个动作上经 `sec-run` 自动带上，没有 sops 密钥的主机启动不了沙箱。secret 集合属于能力上限，主 VM 下次启动会重建一次

token 由用户写进外部 secrets 仓库的 `github/agent-token`，本仓库不含任何 token 值。这个键必须先存在于 `secrets` 输入，否则主机激活时读不到它

## 限制

这是路由，不是安全边界。agent 仍可：

- 用 `gh api`、`gh pr create` 等不在规则表内的命令，它们用的是用户身份：宿主上是 `gh` 的登录态（`~/.config/gh/hosts.yml`），沙箱里是 `GITHUB_TOKEN` 占位符
- 直接调用 Nix store 里的真实 `gh`，或用 `gh auth token` 取出用户 token 再交给 `curl`
- 在 issue 或 PR 命令里用被当作链接的参数值（如 `-b` 的正文恰好是一条链接）影响 owner 判断

宿主上用户 token 已不在 agent 的环境变量里（`sec-run` 不注入它），但 `gh` 的登录态仍可读。要真正拦住，需让 agent 读不到这份登录态，或在 guard 的 `deny_commands` 加规则

## 测试

```bash
bash modules/features/ai/agent-gh/test.sh
```

用假 `gh` 打印收到的 `GH_TOKEN` 与参数，不联网。需要 bash 4 以上
