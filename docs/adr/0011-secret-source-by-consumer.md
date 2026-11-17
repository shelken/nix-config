# 私密值按消费者分两处存放：机器用的进 secrets.nix，人用的进 1Password

日期: 2026-11-17

私密值有两个来源：外部仓库 secrets.nix（sops 密文，以及明文 nix），和 1Password。原先的划分是「用户手动维护的放 1Password，不常变的放 secrets.nix」，按变化频率分，一个值常常两边都说得通，结果同一个 MAC 地址在两处各存一份（路由器的 DHCP 保留与 k8s 节点的网卡配置）。

现在只问一个问题：**主机在没有人值守时需要这个值吗？** 包括启动、激活、服务运行，以及部署时渲染配置。

## 规则

| 回答                                                   | 存放                        | 读取方式                                                                                              |
| ------------------------------------------------------ | --------------------------- | ----------------------------------------------------------------------------------------------------- |
| 需要，且是机密                                         | secrets.nix 的 sops 密文    | 主机用自己的 age 密钥解密（sops-nix）；不能跑 sops 的设备（如 OpenWrt 路由器）由部署机 `sops -d` 渲染 |
| 需要，私有但不机密（实体设备的 MAC、内网拓扑、主域名） | secrets.nix 的明文 nix 文件 | 求值期 `import (inputs.secrets + "/…")`                                                               |
| 不需要：只有人，或用户自己的交互工具在用               | 1Password                   | 人直接查看；交互工具经 `sec-run` 注入环境变量（凭据基座）                                             |

- 每个值只有一个来源。人也要用的机器值（如 Wi-Fi 密码），源头在 secrets.nix；1Password 里可以放一份副本，条目里写明「副本，源在 secrets.nix」，改值时以 secrets.nix 为准。
- 只有实体设备的标识（MAC 等）算私密。服务（k8s 工作负载）的 MAC 是手动随机生成的配置，不是设备标识：它与其推出的 IPv6 后缀直接明文写在 nix-config 里，旁边注明对应的 home-ops 应用。
- 主机的启动与部署不依赖 1Password：无人值守的机器上没有可用的 1Password 会话。

## 考虑过的替代方案

- **按变化频率划分**（原做法）：边界取决于主观判断，同一类值会落到两边。
- **全部放 1Password**：主机解密要依赖 service account token 和网络，启动路径上多一个外部依赖；sops-nix 已在 VPS 与 k8s 节点上使用。
- **全部放 secrets.nix**：网站登录、恢复码这类只有人用的值，没有理由进仓库；交互工具的 API key 轮换频繁，在 1Password 里改更直接。

## 后果

- 路由器（`hosts/router-mine`）的值已按规则搬完，声明与 `just/router.just` 里不再有 `op://`：
  - Wi-Fi 的 SSID 与密码、ZeroTier 的 secret、network-id、device 在 secrets.nix 的 `sops/secrets/hosts/router-mine.yaml`；部署机上 `just router::*` 用 `sops -d` 解密，把值渲染进 `uci.json`，明文只落在临时目录。
  - DHCP 保留的 MAC：k8s 节点读各自 `hosts/<节点>/network.nix` 的 `lanMac`，与节点配置共用一份；其余实体设备在 `hosts/router-mine/network.nix`（明文 nix）。
  - 防火墙放行规则的 4 个 IPv6 后缀由 home-ops 里各应用的 Multus 固定 MAC 推出，属于服务配置，明文写在 `hosts/router-mine/home-ops/firewall.nix`。
- 1Password 的 `router-mine` 条目只剩副本：Wi-Fi 密码等人也要看的值标注「副本，源在 secrets.nix」，其余可删。
- singbox-config 留在 1Password：模板里的值只在用户手动运行生成器时读取；机器无人值守时要读的只有生成结果（旁路由的订阅 URL），它已在 sops 里。
- 凭据基座（`opSecretMap`）只服务交互工具，范围不变。
- 路由器的 sops 文件只有 admin_mio 能解密：路由器是 OpenWrt，不跑 sops，部署只能在 mio 上做。
- sops-nix 是否是主机侧解密的最佳实现另行评估；本规则只决定值的来源，不依赖具体的解密工具。
