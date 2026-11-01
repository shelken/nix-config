# 静态资源用带 rev 的 flake input 锁定

日期: 2026-11-01

他人维护、本仓库只锁版本并原样使用的文件树（`GLOSSARY.md` 里的静态资源）此前由 nvfetcher 锁定：源写在仓库根的 `nvfetcher.toml`，锁定结果落进 `_sources/generated.{json,nix}`，再由每日定时 workflow 逐源开 PR。这条链路把「源版本」放成了与 flake 平行的第二套事实来源：升级要等 workflow、要跑 nvfetcher，Renovate 也看不见这些源。现在它们改成 `flake = false` 的 flake input，交给 Renovate：URL 写成 `git+https://<host>/<owner>/<repo>?ref=<默认分支>&rev=<sha>&shallow=1`，锁出来 `original` 同时有 `ref` 与 `rev`，Renovate 的 nix manager 拿到 currentValue 与 currentDigest，只替换 `flake.nix` 里的 rev。哪些 skill 用哪个 input、取仓库内哪些目录，声明在 `modules/features/ai/_skill-sources.nix`

## 考虑过的替代方案

- **全部留在 nvfetcher**：升级依赖一条定时 workflow 与一次本地 nvfetcher 运行；`_sources` 与 flake 平行，Renovate 永远看不到这些源，也无法按源评估
- **`github:` 型 input**：Nix 的 github fetcher 拒绝同时给 `ref` 与 `rev`（`contains both a commit hash and a branch/tag name`），而 Renovate 只在 `original` 同时有 `ref` 与 `rev` 时才按 input 开 digest PR。只给 `rev` 时 currentValue 为空，lookup 直接判 `invalid-value`；只给 `ref` 时只能记 lockedVersion，只能靠 lockFileMaintenance
- **只靠 `lockFileMaintenance`**：一次把 nixpkgs 与所有源一起推进，无法按源分开评估；skill 类源的内容会直接进 agent 上下文，需要逐个看 diff
- **每个源包一层子 flake**：源本身不是 flake，包一层只是多一层间接，Renovate 也只多认一层
- **保持 tarball（`fetchFromGitHub`）取源**：内容与 nvfetcher 完全一致，但 tarball 型 input 的锁定信息里没有可替换的 rev，Renovate 无法逐 input 开 PR

## 后果

- `ref` 必须写默认分支名（不带 `refs/heads/` 前缀）：git-refs datasource 的 release version 去掉了这个前缀，写全了 `getDigest` 就匹配不到，PR 不会出现
- `shallow=1` 让锁定信息里没有 `revCount`；静态资源只需要一棵树，不受影响
- 含 `.gitattributes` eol 规则的仓库在 git 输入下与 tarball 内容不同：`reverse-skill` 的 23 个 `*.ps1` 会从 CRLF 变 LF，该源已因此移除；其余源的 narHash 与 nvfetcher 的 tarball 一致
- skill 类静态资源逐 input 人工合并，非 skill 静态资源（雾凇拼音、kitty 图标）的 digest 更新自动合并；不写 rev 的 flake 依赖仍靠每周一次的 lockFileMaintenance
- 上游 skill 内容变化时，一个 workflow 会按 `flake.skillSourceDirs` 把「已启用目录」内的文件 diff 贴进 Renovate PR
