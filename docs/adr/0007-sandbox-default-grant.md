# 0007 沙箱上下文默认放行的私网端口

日期: 2026-10-24
状态: Accepted
关联: 修订 [ADR 0002](0002-single-main-vm-execution-context.md) 决策 2「网络只放行项目声明的目标」；「IP 必须在 `network.allow` 内」已被 [ADR 0009](0009-sandbox-trust-approval.md) 取消

## 背景

家里的模型服务（`cpa.int.ooooo.space`、`commandcode.int.ooooo.space`）都解析到私网 `192.168.69.46`。执行上下文默认拒绝全部私网，所以每个项目都要在 `.sandbox.yaml` 声明这个 IP，OMP 才能调用模型；不声明时默认模型请求反复重试，表现为卡住。模型服务是每个 Agent 都要用的基础依赖，不属于某个项目。

## 决策

`sb.yaml` 新增 `network.default_grant`，列出所有执行上下文默认放行的私网目标，只接受 `IP:端口`。当前只放行 `192.168.69.46:443`。

- 范围按端口收窄：同一台机器的其他端口仍需项目声明
- `default_grant` 是上下文级授权，不写进 VM 配置，不改变上限指纹，修改后下一个新上下文即生效，不触发重建

## 考虑过的替代方案

- **按 IP 整体默认放行**：配置更简单，但所有项目都能访问该机器上的全部服务
- **保持每个项目声明**：不改代码，但每个新项目都要先写 `.sandbox.yaml` 才能用 OMP
