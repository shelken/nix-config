# gh

让 agent 在用户自己的仓库里发 issue 和评论时使用专属 GitHub 身份而非本人身份。本功能提供的 `gh` 即 `agent-gh` 包装，宿主与沙箱共用

## 限制

这是路由，不是安全边界。所有经 `sec-run` 启动的程序（如 zed）都算 agent 上下文，且 agent 仍可：

- 用 `gh api`、`gh pr create` 等不在规则表内的命令走用户身份（宿主上是 `~/.config/gh/hosts.yml`，沙箱里是 `GITHUB_TOKEN` 占位符）
- 直接调用 Nix store 里的真实 `gh`，或用 `gh auth token` 取用户 token，或在参数正文放链接影响 owner 判断
- 宿主上 `sec-run` 不注入用户 token，但 `~/.config/gh/hosts.yml` 登录态仍可读；要真正拦住需阻断读取或在 guard 的 `deny_commands` 加规则
- `AGENT_GITHUB_TOKEN` 缺失或为空时，`agent-gh` 直接回落执行当前运行环境的原生 `gh`，按当前 `gh` 凭据（环境变量 `GH_TOKEN`/`GITHUB_TOKEN` 优先于本机登录态）执行，可能以本人身份发布

## 测试与附带命令

```bash
bash modules/features/dev/gh/test.sh
```

附带 `gh-fetch` 按 GitHub 网页地址下载单文件或目录，用法见 `gh-fetch -h`
