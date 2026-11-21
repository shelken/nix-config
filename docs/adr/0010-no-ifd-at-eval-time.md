# 求值期不依赖构建（无 IFD）

日期: 2026-11-17

求值依赖构建（IFD）会让「在一台机器求值、在另一台构建」的流程失败：#335 从 mac 用 nixos-anywhere 装 x86_64 节点，求值机要先构建目标平台 derivation，产物无签名被拒

## 规则

- 求值期 MUST NOT 读取构建产物（`import`、`readFile`、`fromJSON` 等作用于 derivation 输出），MUST NOT 读 YAML；需要其内容的产物 MUST 放到构建期（`runCommand`）或运行时生成
- 全仓核对入口：`just check-ifd`

## 后果

- 没有 CI 守卫，新增 IFD 靠本地 `just check-ifd` 发现；求值失败的主机（读私有 secrets、测试主机断言）被跳过
- 三处原 IFD 的现行实现：catppuccin 取源码（`modules/features/system/catppuccin.nix`）、agent 角色静态规则（`modules/features/ai/agents/default.nix`）、pi models 构建期生成（`modules/features/ai/pi/default.nix`）
