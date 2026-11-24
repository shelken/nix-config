# 私密值按消费者分放 secrets.nix 与 1Password

日期 2026-11-17

私密值原先按变化频率划分到 `secrets.nix` 和 1Password，边界依赖主观判断，导致同一数据在两处重复存放。现在唯一判据为主机在无人值守时（启动、激活、服务运行、部署渲染）是否需要该值

## 规则

- 每个私密值必须只有一个权威来源
- 无人值守需要且机密的值必须存放在 `secrets.nix` 的 sops 密文中，由主机用自身 age 密钥解密，不支持 sops 的设备由持有对应密钥的部署机解密渲染
- 多台主机共享的无人值守机密必须存放在按共享范围命名的单个 sops 文件中（如 `sops/secrets/k8s.yaml`），通过 `.sops.yaml` 多 recipient 授权给对应主机解密，不得按主机复制同一份机密
- 不需要读取任何 sops 机密的主机不得空载导入 `nixos.sops`
- 无人值守需要、私有但不机密的值（实体设备 MAC、主域名、服务商分配的网络参数）必须存放在 `secrets.nix` 的明文 nix 文件中，在求值期读取（`main-domain` 目标归属为明文 nix，当前存量暂留 sops 待迁出）
- 仅由人或交互式工具使用的值必须存放在 1Password 中：Agent 凭据经凭据基座（`Agent` vault）注入，高危人工交互工具（如 `dnscontrol`、`singbox-config`）应当存放在独立非 `Agent` vault 并经桌面 App 授权按需读取
- 人也要查阅的机器值，权威来源必须在 `secrets.nix`，1Password 可以保留副本并标注来源
- 只有实体设备标识算私密，手动随机生成的服务配置（如 k8s 工作负载 MAC 与其 IPv6 后缀）不得当作私密值，直接明文写在公开仓库中
- RFC 1918 私网、Tailscale 内网拓扑地址及主机服务端口（如 SSH 端口）不视为私密值，不得当作私密值迁入 `secrets.nix`，必须直接明文写在公开仓库 `vars/networking.nix` 中
- 主机的启动与部署路径不得依赖 1Password
- 用户态定时任务可以作为例外经 service account 读取 1Password 中凭据基座已有的 key，因为它们不在启动与部署路径上，不得为此在 sops 中重复存一份

## 考虑过的替代方案

- 按变化频率划分。边界模糊，同一类值会落入两处
- 全部放 1Password。主机启动路径多出网络与 service account token 外部依赖
- 全部放 `secrets.nix`。纯个人凭据不应进仓库，高频轮换的 API key 在 1Password 中维护更直接
- 多台虚拟节点共享同一把 age 私钥。放宽了单机吊销边界
