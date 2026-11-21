# 私密值按消费者分两处存放：机器用的进 secrets.nix，人用的进 1Password

日期: 2026-11-17

私密值原先按变化频率划分（用户手动维护的放 1Password，不常变的放 secrets.nix），边界靠主观判断，同一个 MAC 地址在两处各存一份。现在只问一个问题：主机在无人值守时需要这个值吗？包括启动、激活、服务运行与部署时渲染配置

## 规则

- 每个值 MUST 只有一个来源
- 无人值守需要且机密：MUST 存 secrets.nix 的 sops 密文，主机用自己的 age 密钥解密（sops-nix）；不能跑 sops 的设备（如 OpenWrt 路由器）由部署机 `sops -d` 渲染
- 无人值守需要、私有但不机密（实体设备的 MAC、内网拓扑、主域名）：MUST 存 secrets.nix 的明文 nix 文件，求值期 `import (inputs.secrets + "/…")` 读取
- 只有人或用户交互工具在用：MUST 存 1Password，人直接查看，交互工具经 `sec-run` 注入环境变量（凭据基座）
- 人也要用的机器值（如 Wi-Fi 密码）：源头 MUST 在 secrets.nix，1Password MAY 放一份副本并注明「副本，源在 secrets.nix」，改值以 secrets.nix 为准
- 只有实体设备的标识（MAC 等）算私密；手动随机生成的服务配置（如 k8s 工作负载 MAC 与其 IPv6 后缀）MUST NOT 当设备标识，直接明文写在 nix-config 里
- 主机的启动与部署 MUST NOT 依赖 1Password，无人值守机器上没有可用的 1Password 会话
- 例外（2026-11-18）：用户态定时任务 MAY 经 service account 读 1Password（任务 `secrets` 写 `op://` 引用，用的是凭据基座里同一个 key），它不在启动与部署路径上，取不到值只让该任务失败，MUST NOT 为它在 sops 里再存一份

## 考虑过的替代方案

- 按变化频率划分：边界取决于主观判断，同一类值落到两边
- 全部放 1Password：主机解密依赖 service account token 与网络，启动路径多一个外部依赖
- 全部放 secrets.nix：只有人用的值没有理由进仓库，交互工具的 key 轮换频繁

## 后果

- 路由器（`hosts/router-mine`）的值已按规则搬完，声明与 `just/router.just` 里不再有 `op://`：Wi-Fi 与 ZeroTier 进 `secrets.nix` 的 sops 密文，实体设备 DHCP MAC 进 `secrets.nix` 的明文 nix，服务防火墙 IPv6 后缀明文写在 `hosts/router-mine/home-ops/firewall.nix`
- singbox-config 留在 1Password：模板值只在用户手动运行生成器时读取，机器要读的只有生成结果（旁路由订阅 URL），它已在 sops
- 凭据基座（`opSecretMap`）服务交互工具；定时任务不经 sec-run 整份注入，按各自声明的 `op://` 引用逐个读取
- 路由器不跑 sops，部署 MUST 在持有对应解密密钥的部署机上执行（当前仅 `admin_mio` 可解密）
- sops-nix 是否是主机侧解密的最佳实现另行评估，本规则只决定值的来源，不绑定解密工具
