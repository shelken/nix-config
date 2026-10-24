# 0008 导入文件的目标路径与来源上限

日期: 2026-10-24
状态: Accepted（决策 4 已被 [ADR 0009](0009-sandbox-trust-approval.md) 取代）
关联: 修订 [ADR 0002](0002-single-main-vm-execution-context.md) 中 `imports` 的落地方式与「`imports.source` 不受挂载根限制」；背景见 #130

## 背景

`imports` 只能把文件放到上下文内的 `/imports/<文件名>`。home-ops 这类项目用 mise 把 `KUBECONFIG` 固定为 `$HOME/.kube/home-ops.yaml`，工具只认这个路径，所以没法用。

另外，`.sandbox.yaml` 在项目仓库里，Agent 能改，下次启动生效。`imports.src` 又没有任何上限，Agent 改一行就能把 `~/.ssh` 下的私钥带进上下文。

## 决策

1. **`imports` 每项写 `src` 与 `target`**。`target` 是上下文内的路径，以 `~/`（上下文的家目录）或 `/` 开头，不含 `..`，必须位于某个子目录内。去掉 `/imports` 与 `dest`、`dst`、`name` 别名。
2. **按目标目录绑定暂存目录**。同一目标目录的导入共用一个暂存目录，launcher 把它整体绑定到该目录，不做单文件绑定，否则上下文内的原子改名会报 `Device or resource busy`（ADR 0002 已实测）。代价：目标目录在上下文里只剩导入的文件。
3. **保留位置不能做目标目录**：家目录本身、`/`、系统目录、`/data`、`/run`、`/.msb`，以及 launcher 铺设配置链接的 `~/.omp`、`~/.agents`、`~/.pi`。同一个 `target` 不能重复。
4. ~~`sb.yaml` 新增 `import_sources`~~：已被 ADR 0009 取代。`imports.src` 不再有预先登记的上限，是否放行由 `sb trust` 的批准决定。
5. 导入文件在上下文内只对上下文用户可读写（`600`）。

## 不做

- OAuth 登录态不导入。OMP 的登录态在 `agent.db`，位于共享的 `/data/xdg/data/omp`，在沙箱里登录一次即可持久化并被所有项目共用。
- 写回宿主。上下文内的修改仍然随上下文退出丢弃。

## 考虑过的替代方案

- **不设来源上限**：配置少一项，但 Agent 改 `.sandbox.yaml` 就能扩权
- **单文件绑定**：目录遮蔽的副作用消失，但原子改名失败
- **把凭据放进 `/data` 持久化**：`/data` 绑进所有上下文，项目凭据会对其他项目可见
