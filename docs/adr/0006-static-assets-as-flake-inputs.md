# 静态资源用带 rev 的 flake input 锁定

日期 2026-11-01

仓库引用的第三方静态资源原先由 nvfetcher 锁定在 `nvfetcher.toml` 与 `_sources/`，与 `flake.lock` 形成两套版本来源，Renovate 无法识别。现在全部静态资源改为 `flake = false` 的 flake input，由 Renovate 统一推进版本

## 规则

- 静态资源 input 的 URL MUST 采用 `git+https://<host>/<owner>/<repo>?ref=<默认分支>&rev=<sha>&shallow=1` 形式
- `ref` MUST 写默认分支名且不带 `refs/heads/` 前缀，否则 Renovate 的 git-refs 数据源匹配不到更新
- 静态资源 input MUST 带 `shallow=1`

## 考虑过的替代方案

- 继续使用 nvfetcher。版本来源与 flake 分裂，升级依赖单独的定时 workflow，Renovate 看不到这些源
- 使用 `github:` 型 input。Nix 的 github fetcher 拒绝同时指定 `ref` 与 `rev`，而 Renovate 只有同时看到两者才会逐 input 开 digest PR
- 只依赖每周一次的 `lockFileMaintenance`。nixpkgs 与所有外部 skill 混在同一个 PR，无法对直接进入 agent 上下文的 skill 单独审 diff
- 使用 tarball 形式取源。锁定信息没有可替换的 `rev`，Renovate 无法按 input 更新
