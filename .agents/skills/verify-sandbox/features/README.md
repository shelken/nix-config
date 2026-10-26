# Agent 沙箱验证地图

本目录是沙箱用户可见行为的验证来源。驱动前读本索引，再按对应 feature 文件执行

## 基线前置

- 已执行 `verify.sh setup`，`verify.sh doctor` 全部通过
- 测试项目 `$HOME/Code/sb-verify-<RUN>` 是只有一个初始提交的 git 仓库，没有 `.sandbox.yaml`
- 只驱动本次 `SB_VERIFY_RUN` 创建的实例；不要对 `~/Data/sandboxes/msb` 执行任何命令

## 驱动约定

- 下文 `$V` 指 SKILL.md 中定义的绝对路径；先执行 `eval "$($V paths)"` 得到 `$WORK`、`$PROJ`、`$EVIDENCE`
- 沙箱命令一律 `$V sb …`，guest 旁证一律 `$V msb exec sb-main -- …`
- 调 OMP 一律 `--model=cpa/gpt-5.6-luna`，并加 `timeout`
- 修改了 `$WORK/sb.yaml` 或测试项目 `.sandbox.yaml` 的步骤，结束后恢复

## 证明与跳过

- CLI 证明包含命令、stdout、stderr、退出码，用 `$V run <名字> -- …` 记录
- 状态变化前后各取一次 `$V sb status`
- 无法到达的路径记录尝试的命令和缺失的前置条件，不用另一个入口代替

## 功能条目约定

每个文件以 H1 和一段用户可见行为开头，然后依次是 `Sub-features`、`How to get to it (user POV)`、`Driving it with verify.sh`、`Gotchas` 四个 H2

## 功能

- [首次启动](./first-start.md)：自动建卷、建 VM、首次 sync，`sb status` 就绪
- [OMP 调用模型](./omp-model.md)：上下文内 OMP 建库、发现模型、完成一次对话
- [隔离与并发上下文](./isolation-concurrency.md)：相邻项目、私网、secret、worktree，多个上下文互不打断
- [工具补齐](./sync.md)：重复 sync 零下载、并发 sync 串行、私有插件、沙箱内无法装工具
- [生命周期与授权](./lifecycle-grants.md)：上限变化重建或拒绝、`sb rm`、宿主命令桩、`.sandbox.yaml` 授权
- [声明配置只读、运行状态可写](./declared-config.md)：声明文件与祖先目录挂载强制只读，兄弟可写且跨上下文共用，残留占位预检
