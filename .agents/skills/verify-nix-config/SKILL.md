---
name: verify-nix-config
description: 验证 nix-config 的 Darwin/Home Manager CLI 变更时使用，包括 just hm-build、just bd、Home 与系统 activationPackage 同源检查，以及经授权的 just hm/just sw 生效验证
---

# nix-config 真实验证

主要 surface 是仓库根目录的 `just`/`nh` CLI，用户通过它构建或切换 Darwin 与 Home Manager 配置。NixOS 是次要 surface，只做目标主机的轻量求值，除非任务明确授权远程部署

先读 [`features/README.md`](features/README.md)，再按变更影响选择所有对应 feature。一次方便入口的成功不能替代 map 中其他受影响入口

## Doctor

build helper 内置 `doctor`，无需提前重复运行。仅检查前置条件或准备 switch 时单独执行：

```bash
./.agents/skills/verify-nix-config/scripts/verify.sh doctor
```

它匹配当前 `LocalHostName` 与 `darwinConfigurations` 的 `networking.hostName`，也可用 `VERIFY_HOST=<flake-attr>` 显式选择本机输出。它不读取 `.host-profile`，检查：

- `nix`、`just`、`nh`、`jq`、`git` 可用
- 当前机器存在 Darwin 与 Home 输出
- 系统 Home 与 `homeConfigurations` 的 activationPackage drvPath 相同
- `useUserPackages = false`
- `enableLegacyProfileManagement = true`
- Home profile 不在系统 `/etc/profiles/per-user` 环境

检查失败即停止。找不到 hostname 匹配时，设置 `VERIFY_HOST` 后重跑；build helper 将已检查的主机通过 `just --set profile` 传给构建入口，避免被 `.host-profile` 或环境中的 `PROFILE` 改变目标

## Drive

使用 Bash harness，稳定 handle 是 flake attr、derivation path、profile symlink 和命令退出码

- Home 局部构建：读 [`features/home-partial-build.md`](features/home-partial-build.md)，运行 `verify.sh home-build`
- Darwin 系统构建：读 [`features/darwin-system-build.md`](features/darwin-system-build.md)，运行 `verify.sh darwin-build`
- Darwin defaults 回读：读 [`features/darwin-defaults-readback.md`](features/darwin-defaults-readback.md)，运行 `verify.sh defaults`，用于证明偏好值确实落到系统存储
- Home 局部切换：读 [`features/home-partial-switch.md`](features/home-partial-switch.md)，仅在任务明确授权应用用户态配置时运行 `just hm`
- Darwin 系统切换：读 [`features/darwin-system-switch.md`](features/darwin-system-switch.md)，仅在任务明确授权完整系统 switch 时运行 `just sw`

build 可并行存在于 Nix store。switch 共享当前机器的 system、Home profile、文件和服务，拒绝并发 drive，也不把其他会话启动的实例当作自己的测试对象

## Evidence

helper 默认写入：

```text
${TMPDIR:-/tmp}/verify-nix-config-evidence/<UTC>-<host>-<feature>-<pid>/
```

可用 `VERIFY_EVIDENCE_DIR=<dir>` 指定目录。保留以下 proof：

- `metadata.txt`：feature、host、用户、Git revision、工具版本
- `working-tree.txt`：运行时工作树状态
- `doctor.txt`：同源与 profile 门禁
- `transcript.log`：真实 `just` 命令、stdout、stderr
- `before-links.txt` / `after-links.txt`：system 与 Home profile 链接
- `summary.json`：命令退出码、drvPath 和共享链接是否变化

proof 同时包含动作和结果。build 比较 profile 链接前后不变；switch 还需从消费者确认副作用，例如解析 CLI、检查生成文件或查询服务。偏好回读只证明存储层，应用效果需查询消费该偏好的原生 API 或观察实际行为

## Cleanup

build helper 保留 evidence，不创建额外临时目录。Nix store 中的构建结果保留供后续验证

switch 修改共享机器状态，无法隔离成并行实例。验证完成后保留已授权的目标状态；回滚属于新的系统变更，只能在明确授权后运行仓库的 `just rollback`
