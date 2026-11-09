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
| 构建 | [_package.nix](./_package.nix) 用 `writeShellApplication`，`runtimeInputs` 让脚本里的 `gh` 解析到真实 `gh` |

token 由用户写进外部 secrets 仓库的 `github/agent-token`，本仓库不含任何 token 值。合并前先加密钥并更新 `secrets` 输入，否则主机激活时读不到这个键

## 限制

这是路由，不是安全边界。agent 仍可：

- 用 `gh api`、`gh pr create` 等不在规则表内的命令，它们用的是环境里的 `GITHUB_TOKEN`
- 直接调用 Nix store 里的真实 `gh`，或用 `curl` 带上 `GITHUB_TOKEN`
- 在 issue 或 PR 命令里用被当作链接的参数值（如 `-b` 的正文恰好是一条链接）影响 owner 判断

要真正拦住，需把用户 token 移出 agent 环境，或在 guard 的 `deny_commands` 加规则

## 测试

```bash
bash modules/features/ai/agent-gh/test.sh
```

用假 `gh` 打印收到的 `GH_TOKEN` 与参数，不联网。需要 bash 4 以上
