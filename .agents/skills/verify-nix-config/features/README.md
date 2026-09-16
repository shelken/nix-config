# nix-config verification map

这里是 nix-config 用户可见 CLI 行为的验证索引。先读本页，再打开所有受变更影响的 feature 文件

## Baseline preconditions

- 从仓库根目录运行命令
- 当前机器安装 `nix`、`just`、`nh`、`jq`、`git`
- 使用 `verify.sh doctor` 动态解析当前 Darwin flake attr，不读取 `.env`
- build 可共享 Nix store，但 proof 目录必须独立
- switch 修改共享 system/Home 状态，同一时间只允许一个 drive，并要求任务明确授权

## Driving conventions

- Bash harness 为 `.agents/skills/verify-nix-config/scripts/verify.sh`
- build 先运行 doctor，再执行仓库公开的 `just` 入口
- 稳定 handle 使用 flake attr、drvPath、profile symlink、生成文件与 CLI 解析结果
- `VERIFY_HOST=<flake-attr>` 只用于 hostname 无法唯一匹配时
- `VERIFY_EVIDENCE_DIR=<dir>` 用于固定 proof 目录
- 不使用固定 sleep，命令退出就是短命 CLI 的完成信号

## Proof and skip reporting

- CLI proof 包含原命令、stdout、stderr、退出码
- build proof 还要比较 system/Home profile 链接前后不变
- switch proof 同时记录 action 和真实副作用，不能只保留 activation 成功日志
- dry-run 或 build 的安全性通过观察 profile、文件、网络或 Git ref 证明，不依赖命令名称
- 无法到达的入口记录原命令与未满足前置条件，不能用另一个入口的成功代替
- cleanup 删除 scratch，保留 evidence

## Feature entry contract

每个 feature 文件从用户视角描述行为，并严格使用四个 H2：

1. `Sub-features`
2. `How to get to it (user POV)`
3. `Driving it with Bash`
4. `Gotchas`

## Features

- [Home partial build](./home-partial-build.md)：构建当前机器的 Home 局部输出，并证明它与系统 Home 同源且不切换 profile
- [Darwin system build](./darwin-system-build.md)：构建当前机器 Darwin toplevel，并证明 build 没有切换系统或 Home
- [Home partial switch](./home-partial-switch.md)：经授权应用 Home 局部配置，并从用户入口确认文件、包或服务副作用
- [Darwin system switch](./darwin-system-switch.md)：经授权切换完整 Darwin system，并确认 system generation 与内嵌 Home 激活结果
