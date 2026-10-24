# 0009 项目授权由宿主侧批准决定，私网在 VM 级整体放开

日期: 2026-10-24
状态: Accepted
关联: 修订 [ADR 0002](0002-single-main-vm-execution-context.md) 中网络与导入文件受能力上限约束的部分；取代 [ADR 0008](0008-sandbox-import-target.md) 决策 4（`import_sources`）；[ADR 0007](0007-sandbox-default-grant.md) 的 `default_grant` 不再要求 IP 在 `network.allow` 内；背景见 #132

## 背景

按 ADR 0002，`sb.yaml` 的 `network.allow` 逐项列出项目可以申请的私网 IP，并写进 msb 的 VM 配置。这带来两个问题：

1. 改授权就要重建主 VM。重建要求没有 Agent 在运行，日常同时开着多个 Agent 时几乎总被挡住
2. 上限是全局的。一个 IP 放进 `allow` 后，任何项目的 `.sandbox.yaml` 都能申请，而 `.sandbox.yaml` 在仓库里，Agent 改了就在下次启动生效

实测 msb 的 `allow` 支持 `private` 目标组：只写 `public` 时对内网 kube-apiserver 的明文 HTTP 请求被拒绝连接，加上 `private` 后收到应用层的 `400 Bad Request`。而每个执行上下文的 iptables 链本来就按源地址逐项限制私网目标（`launcher.sh`），VM 级逐项列 IP 是重复的一层。

## 决策

1. **VM 级放开私网**：`sb.yaml` 的 `network.allow` 写 `public`、`dns`、`private` 与 `host:tcp:<端口>`，不再逐项列 IP。逐项限制只由上下文内的 iptables 链完成。
2. **`sb trust` 批准项目授权**：项目有 `.sandbox.yaml` 时，`sb run`、`sb shell`、`omp-sb` 要求它已批准，否则直接报错并给出 `sb trust` 命令，不弹提示、不等待输入。`.sandbox.yaml` 不存在时不需要批准。
3. **批准只看内容哈希**：对键排序、去注释后的规范化 JSON 取 SHA-256，记录在 `$MSB_HOME/approvals/<哈希>`。不看项目路径，所以同一份文件在所有 worktree 里只批准一次；只改注释或格式不失效；内容一变（包括 Agent 修改）就要重新批准。
4. **批准记录在宿主上**：沙箱里的 `sb` 被宿主命令桩拒绝，Agent 批准不了自己。
5. **删除网络上限与 `import_sources`**：`.sandbox.yaml` 的 `network` 只校验写法（`IP` 或 `IP:端口`），`imports.src` 只校验文件存在，是否放行由批准决定。`paths` 仍受 `mount_roots` 限制，因为挂载是 VM 级的；同时也计入批准。
6. **`sb plan` 显示批准状态**，`sb trust` 在批准后打印同一份清单。

## 后果

- 改授权（新增一个 IP、换一个导入文件）不再触发 VM 重建，也不被运行中的 Agent 挡住
- Agent 改 `.sandbox.yaml` 不再自动扩权，下次启动前必须由用户重新批准
- 不在上下文里运行的 guest 进程（`sb sync` 的 mise 与 `bun install`、`msb exec` 进入的 root 进程）不受上下文链约束，也能连私网。威胁模型只防 Agent 误操作，Agent 始终在上下文内，所以接受，并在沙箱 README 的已知局限里写明
- 批准不覆盖 `imports.src` 指向的宿主文件的内容变化
- 改 `network.allow` 的 VM 级策略仍会改变上限指纹、触发一次重建（部署本变更时发生一次）

## 考虑过的替代方案

- **保留逐项上限、只放宽重建条件**：不改变信任模型，Agent 改文件仍然自动扩权
- **批准按路径加哈希**：同一份文件在每个 worktree 里都要重新批准，没有收益
- **交互式提示**：在后台、脚本、自动开 Agent 的场景会卡住
- **宿主侧项目授权文件（不进仓库）**：原本为公开仓库不能写内网 IP 设计，核实后仓库已大量包含内网 IP，这个理由不成立，需要时再加
