# k3s-node

NixOS 上的 k3s 集群节点：`services.k3s` + Longhorn 所需的 iSCSI/NFS + 内核与时钟调优。可选功能，由 `hosts/k8s/common.nix` 导入

- 选项 `shelken.k3s`：`role`（`server`/`agent`，必填）、`nodeLabels`、`nodeIP`（默认取 `vars/networking.nix` 里同名主机）
- k3s 配置以 home-ops 原 Ansible 渲染结果为准；`package` 写死 `k3s_1_37`，升级 minor 先 server 后 agent
- agent 的令牌来自共享 sops 文件 `sops/secrets/k8s.yaml` 的 `k3s-token` 键（worker 主机需导入 `self.modules.nixos.sops`），server 不读它也无需导入 `sops`（令牌随恢复的 `/var/lib/rancher/k3s/server` 带过来）

| 原 Ansible                                 | 这里                                                                                |
| ------------------------------------------ | ----------------------------------------------------------------------------------- |
| `99-custom.conf`、chrony、cifs、open-iscsi | `boot.kernel.sysctl`、`services.chrony`、`boot.kernelModules`、`services.openiscsi` |
| `audit-policy.yaml`、`registries.yaml`     | 同目录同名文件，进 Nix store                                                        |

`registries.yaml` 的外部端点与 home-ops 的 Gatus 探测清单一一对应，home-ops CI 从本仓库 `main` 读取它校验，改端点时两边一起改
