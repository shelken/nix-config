# 静态资源用带 rev 的 flake input 锁定

日期: 2026-11-01

他人维护、本仓库只锁版本并原样使用的文件树（静态资源）原先由 nvfetcher 锁定，源版本与 flake 平行成第二套事实来源，升级要等 workflow 与本地 nvfetcher，Renovate 看不见这些源。现在改成 `flake = false` 的 flake input 交给 Renovate：URL 写成 `git+https://<host>/<owner>/<repo>?ref=<默认分支>&rev=<sha>&shallow=1`，Renovate 只替换 `flake.nix` 里的 rev。skill 用哪个 input 已改由 `shelken.dev.ai.skills` 登记与 `flake.skillUpstreams` 提供，见 ADR 0009

## 规则

- 静态资源 input 的 URL MUST 同时带 `ref` 与 `rev`：`ref` MUST 写默认分支名且不带 `refs/heads/` 前缀，否则 Renovate 的 digest PR 不会出现；只给 `rev` 时 currentValue 为空判 `invalid-value`，只给 `ref` 时只能靠 lockFileMaintenance
- MUST 带 `shallow=1`，静态资源只需一棵树，无 `revCount` 不受影响

## 考虑过的替代方案

- `github:` 型 input：Nix github fetcher 拒绝同时给 `ref` 与 `rev`，而 Renovate 只在两者同有时才按 input 开 digest PR
- 只靠 lockFileMaintenance：nixpkgs 与所有源一起推进，skill 内容直接进 agent 上下文需要单独审 diff
- tarball（`fetchFromGitHub`）取源：锁定信息里没有可替换的 rev，Renovate 无法逐 input 开 PR

## 后果

- skill 类静态资源每周合成一个 PR 人工合并（评论按 input 分段贴 diff），非 skill 静态资源（雾凇拼音、kitty 图标）digest 更新逐个自动合并，不写 rev 的 flake 依赖靠每周 lockFileMaintenance
- 含 `.gitattributes` eol 规则的仓库在 git 输入下与 tarball 内容不同，`reverse-skill` 已因此移除
