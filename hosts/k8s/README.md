# k8s 节点：重装与日常手册

k3s 集群三台节点：Lima 控制面 `sakamoto-k8s`、Lima worker `yuuko-k8s`、PVE GPU worker `homelab-1`。节点配置（NixOS + `services.k3s`，基线以 `home-ops` 原 Ansible 渲染结果为准）由本仓库声明，集群工作负载由 `home-ops` Flux 管理。**重装节点必须本人在场，每个阶段确认后再继续**

## 组成与跨仓约束

- `common.nix` / `lima.nix` / `<节点>/default.nix`：三台共有与单机声明；worker 导入 `nixos.sops`，控制面不导入 `sops`；`homelab-1` 另含 OpenWrt 构建器（见 [openwrt](../../modules/features/network/openwrt/README.md)）与固定 6.12 内核的 vGPU（见 [k3s-nvidia-vgpu](../../modules/features/homelab/k3s-nvidia-vgpu/README.md)）
- 私有 `secrets`：`hosts/<节点>/network.nix`（明文 MAC）、共享 `sops/secrets/k8s.yaml`（`k3s-token`）与 `homelab-1` 独有 `sops/secrets/hosts/homelab-1.yaml`（`nvidia-client-token`）
- **跨仓约束**：`modules/features/homelab/k3s-node/registries.yaml` 的外部镜像源端点与 `home-ops` 的 Gatus CI 探测清单一一对应，修改端点时须同步检查两边
- **首次启用 `lima-host` 约束**：宿主的 `~/.lima/_disks` 未设 `force` 以防覆盖数据盘，首次在宿主部署 `lima-host` 前须先手动移走旧的 `~/.lima/_disks`

## 重装要带过去的状态

| 状态                        | 节点                               | 目标路径                                            | 怎么带                                      |
| --------------------------- | ---------------------------------- | --------------------------------------------------- | ------------------------------------------- |
| age 私钥                    | worker（`yuuko-k8s`、`homelab-1`） | `/var/lib/sops-nix/key.txt`                         | `--extra-files`                             |
| SSH 主机密钥与节点口令      | 全部                               | `/etc/ssh/ssh_host_*`、`/etc/rancher/node/password` | `--extra-files`（缺口令会被集群拒绝加入）   |
| etcd、CA、加密密钥          | `sakamoto-k8s`                     | `/var/lib/rancher/k3s/server`                       | `--extra-files`                             |
| Longhorn / OpenEBS 本地数据 | `sakamoto-k8s` / `homelab-1`       | `/mnt/lima-longhorn`、`/var/mnt/local-hostpath`     | Lima 附加盘不触碰；PVE 同盘须先经临时卷打包 |

## 重装一台节点

1. **drain**：`kubectl drain <节点> --ignore-daemonsets --delete-emptydir-data`（控制面重装前确认 Flux 无进行中变更）
2. **回滚点**：
   - Lima：先在宿主 `touch ~/.lima/<节点>/no-autostart` 再停机（防止自启动 agent 或卷挂载拉起虚拟机），用 `cp -c`（APFS 克隆）备份实例目录的 `diffdisk`、`datadisk`、`lima.yaml` 以及 `sakamoto-k8s` 的 `~/.lima/_disks/longhorn/datadisk`
   - PVE：必须先 `qm shutdown <vmid>` 再 `qm snapshot <vmid> <名字>` 后启动；运行中快照冻结文件系统会与同盘 Longhorn 副本死锁
3. **准备随装目录** `$EXTRA`（权限规则见 [VPS 指南](../../docs/user-guide/05-vps.md)）后执行两阶段安装（在 `nix develop` 中运行，不手写 nixos-anywhere 参数）：
   ```bash
   just anywhere::kexec <节点> <节点 IP>           # 阶段一：不碰磁盘，卡重连 Ctrl-C，核对 lsblk 与 MAC
   just anywhere::install <节点> <节点 IP> "$EXTRA"
   rm -r "$EXTRA"
   ```
4. **验证并首推**：Lima 节点换上新 `lima.yaml`（宿主 `socket_vmnet` 须先就绪）；核对 `nixos-version`、`eth0`/`eth1`/`eth1.50` 与 `kubectl get node`；立刻执行一次不改配置的 `just deploy <节点>` 建立 deploy-rs 激活器
5. **收尾**：`kubectl uncordon <节点>` 并确认 Longhorn 副本重建；Lima 节点 `rm ~/.lima/<节点>/no-autostart`

### 控制面额外要点

- 打包 `/var/lib/rancher/k3s/server` 前必须**不带数据盘**启动原系统：`limactl stop` 后把 `~/.lima/sakamoto-k8s/lima.yaml` 临时换成去掉 `additionalDisks` 的普通文件再启动打包，完成后删普通文件并 `just deploy sakamoto` 恢复软链
- 装机期间 disko 绝不能看到 Longhorn 数据盘，装完换回声明的 `lima.yaml` 后再挂载；k3s server 不支持降级

## 更新 Lima 实例与宿主 `socket_vmnet`

`~/.lima/<节点>/lima.yaml` 为只读 Nix store 软链，改 `hosts/k8s/lima.nix` 或 `shelken.lima.*` 后在宿主生效并重启实例：

```bash
just deploy <宿主>
ssh <宿主> 'limactl stop <节点>'                 # 失败再 --force 并 limactl disk unlock longhorn
ssh <宿主> 'limactl start --tty=false <节点>'
```

- 重建 `~/.lima` 或换宿主后需将新的 `~/.lima/_config/user.pub` 写入 `vars.limaUserKeys` 并 `just deploy <节点>`
- 桥接 socket `/var/run/socket_vmnet.bridged.<网卡>` 由宿主 `lima-host` launchd 提供（网卡名在 `vars/default.nix` 的 `socketVmnet.interface`），须先让宿主 darwin 生效再启动 Lima 实例

## 整集群关机与开机

顺序：PVE worker → Lima worker → 控制面（开机反序）。直接 `qm shutdown` / `limactl stop`，**不要先停 k3s、不强停、不 drain**：先停 k3s 再断电会在卷挂载期间杀掉 Longhorn 引擎导致脏盘（2026-08-01 事故）

## kubeconfig 与日常更新

控制面重建且 CA 变化时重导 kubeconfig：

```bash
ssh root@sakamoto-k8s cat /etc/rancher/k3s/k3s.yaml | sed 's#https://127.0.0.1:6443#https://192.168.6.80:6443#' > ~/.kube/home-ops.yaml && chmod 600 ~/.kube/home-ops.yaml
```

- 滚动部署：`just k8s::deploy [节点...]`（默认全部，agent 先、控制面最后，每台健康检查通过再继续；底层走 `just deploy <节点>`，使用 `rootDeploy` 直连 root 免密，节点本地构建，30 秒内确认失败自动回滚）
- k3s minor 升级：在 `k3s-node` 有意修改固定版本，先 `sakamoto-k8s` 后 worker
- 加节点：在 `secrets` 补 `hosts/<节点>/network.nix`（worker 另建 age 密钥并更新 `.sops.yaml` 与 `sops/secrets/k8s.yaml`），再新增 `hosts/k8s/<节点>/` 并在 `hosts/default.nix` 注册
