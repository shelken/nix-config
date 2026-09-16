# Home partial build

Home partial build 让用户通过 `just hm-build` 构建整份机器配置中的 Home 子结果，查看差异，但不切换系统或用户 profile

## Sub-features

- `home-build-doctor` 确认当前 host、工具和 Home 同源不变量
- `home-build-command` 运行仓库公开的 `just hm-build` 入口
- `home-build-identity` 确认 Home 与系统内嵌 Home 的 activationPackage drvPath 相同
- `home-build-no-switch` 确认 system 与 Home profile 链接前后不变

## How to get to it (user POV)

- 在仓库根目录运行 `just hm-build`
- 需要保存标准 proof 时运行 `.agents/skills/verify-nix-config/scripts/verify.sh home-build`

## Driving it with Bash

Preconditions:

- `verify.sh doctor` 输出 `doctor=ok`
- 当前工作树包含待验证变更，新增且需要进入 flake 的配置文件已暂存
- evidence 目录不与其他 drive 共用

- **运行真实入口。** 执行 `.agents/skills/verify-nix-config/scripts/verify.sh home-build`。`transcript.log` 中的 nh pipeline 构建 `homeConfigurations.<host>.config.home.activationPackage`，命令退出码为 `0`
- **确认同源。** 读取 `summary.json`。`home_drv` 与 `system_home_drv` 完全相同
- **确认用户 profile。** `profile_dir` 不是系统 `/etc/profiles/per-user` 环境
- **确认无切换。** `shared_profile_links_unchanged` 为 `true`，`before-links.txt` 与 `after-links.txt` 相同
- **保留 proof。** 记录 helper 输出的 `evidence=<dir>`，保留该目录的 transcript、summary 与链接快照

## Gotchas

- build 会写 Nix store，这是预期副作用，成功标准是共享 profile 链接不变
- flake 忽略未追踪文件，新增配置未暂存会产生虚假的成功
- nh 的差异基于当前已激活 generation，可能包含工作树中其他改动，proof 必须保留完整 diff
- `hm-dev-build` 使用本地 secrets override，属于不同入口，不能替代本 feature
