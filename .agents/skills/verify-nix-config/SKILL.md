---
name: verify-nix-config
description: 验证 nix-config 的 Darwin/Home Manager CLI 变更时使用，包括 just hm-build、just bd、Home 与系统 activationPackage 同源检查，以及经授权的 just hm/just sw 生效验证
---

# nix-config 真实验证

主要 surface 是仓库根目录的 `just`/`nh` CLI，用户通过它构建或切换 Darwin 与 Home Manager 配置。NixOS 与 Colmena 是次要 surface，只做目标主机的轻量求值，除非任务明确授权远程部署

先读 [`features/README.md`](features/README.md)，再按变更影响选择所有对应 feature。一次方便入口的成功不能替代 map 中其他受影响入口

## Launch

这是短命 CLI，没有常驻服务或端口。每次 drive 独立运行，开始前执行：

```bash
./.agents/skills/verify-nix-config/scripts/verify.sh doctor
```

输出 `doctor=ok`、flake host、用户名、两个相同的 Home activationPackage drvPath 后，实例才值得继续验证

安全构建入口：

```bash
./.agents/skills/verify-nix-config/scripts/verify.sh home-build
./.agents/skills/verify-nix-config/scripts/verify.sh darwin-build
```

命令退出即完成 teardown。helper 自动删除 scratch，不删除 evidence

## Doctor

`doctor` 是只读门禁：

```bash
./.agents/skills/verify-nix-config/scripts/verify.sh doctor
```

它动态匹配当前系统 hostname 与 `darwinConfigurations` 的 flake attr，不读取 `.env`，并检查：

- `nix`、`just`、`nh`、`jq`、`git` 可用
- 当前机器存在 Darwin 与 Home 输出
- 系统 Home 与 `homeConfigurations` 的 activationPackage drvPath 相同
- `useUserPackages = false`
- `enableLegacyProfileManagement = true`
- Home profile 不在系统 `/etc/profiles/per-user` 环境

任何检查失败都停止 drive。flake attr 无法从 hostname 唯一匹配时，显式设置 `VERIFY_HOST=<flake-attr>` 后重跑

## Drive

使用 Bash harness，稳定 handle 是 flake attr、derivation path、profile symlink 和命令退出码

- Home 局部构建：读 [`features/home-partial-build.md`](features/home-partial-build.md)，运行 `verify.sh home-build`
- Darwin 系统构建：读 [`features/darwin-system-build.md`](features/darwin-system-build.md)，运行 `verify.sh darwin-build`
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
- `transcript.log`：真实 `just` 命令、stdout、stderr、退出码
- `before-links.txt` / `after-links.txt`：system 与 Home profile 链接
- `summary.json`：命令结果、drvPath、一致性和共享链接是否变化

proof 必须同时包含用户动作和结果状态。build 的安全性通过实际比较 profile 链接证明，不能只相信「build」命令名。switch 还要从第二个用户入口确认副作用，例如重新解析 CLI、读取生成文件或查询服务状态。生产边界没有既有 mock 时不用 mock

## Cleanup

build helper 只创建 scratch 与 evidence：

- scratch 在成功、失败和中断时自动删除
- evidence 保留，失败也保留 transcript
- 没有进程可终止，不按进程名 kill

switch 修改共享机器状态，无法隔离成并行实例。验证完成后保留已授权的目标状态；回滚属于新的系统变更，只能在明确授权后运行仓库的 `just rollback`

## Helpers

唯一 helper 已设为可执行：

```bash
# 只读健康门
./.agents/skills/verify-nix-config/scripts/verify.sh doctor

# 构建并保存完整证据
./.agents/skills/verify-nix-config/scripts/verify.sh home-build
./.agents/skills/verify-nix-config/scripts/verify.sh darwin-build

# 为经授权的 switch 保存共享 profile 快照
./.agents/skills/verify-nix-config/scripts/verify.sh snapshot <output-file>

# hostname 与 flake attr 不同或无法自动匹配时
VERIFY_HOST=<flake-attr> ./.agents/skills/verify-nix-config/scripts/verify.sh doctor

# 需要固定 proof 目录时
VERIFY_EVIDENCE_DIR=<dir> ./.agents/skills/verify-nix-config/scripts/verify.sh home-build
```
