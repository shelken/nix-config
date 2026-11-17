# k8s 节点：重装与日常手册

家里 k3s 集群的三台节点：Lima 里的控制面 `sakamoto-k8s`、Lima 里的 worker `yuuko-k8s`、PVE 虚拟机里的 GPU worker `homelab-1`。节点只有 NixOS + `services.k3s`，由本仓库声明；集群里的东西由 home-ops 的 Flux 管

**重装节点必须本人在场，每个阶段确认后再继续。** 本手册是可复用的流程，不记录某次执行的结果

## 组成

- `common.nix`：三台共有：`server` 角色、disko（ext4）、sops、网络（networkd 按 MAC 命名网卡、`eth1` DHCP、VLAN 子接口 `eth1.50`）、`k3s-node` 功能
- `lima.nix`：两台 Lima（vz）节点共有：引导、usernet 网卡 `eth0`、`shelken.lima.*` 选项与 `system.build.limaConfig`（Lima 实例声明的数据，宿主据此生成 `lima.yaml`）
- `<节点>/default.nix`：主机名、磁盘设备、k3s 角色与标签；`sakamoto-k8s` 另有 Longhorn 数据盘的挂载；`homelab-1` 另有 Longhorn 数据分区（与系统同盘）、qemu 驱动与 Intel 核显
- `modules/features/homelab/k3s-node/`：k3s 配置、Longhorn 所需的 iSCSI/NFS、sysctl、chrony，见该目录 README
- `modules/features/homelab/lima-host/`：Lima 宿主（`sakamoto`、`yuuko`）的功能：常驻的桥接 socket_vmnet、`lima.yaml` 与附加盘软链、实例自启动，见该目录 README 与下文「宿主的 socket_vmnet」
- `modules/features/homelab/k3s-nvidia-vgpu/`：`homelab-1` 的 vGPU 驱动与 nvidia 运行时，内核固定 6.12 的原因见该目录 README
- 私有 `secrets` 仓库两类文件：`hosts/<节点>/network.nix`（网卡 MAC，明文，求值期读取）、`sops/secrets/hosts/<节点>.yaml`（`k3s-token`；`homelab-1` 另有 `nvidia-client-token`），只有管理员和该节点自己的 age 密钥能解

## 要带过去的状态

装机抹盘。不在 Nix 配置里、又要保留的东西，自己带过去：

| 状态                         | 节点           | 目标路径                                        | 怎么带                                             |
| ---------------------------- | -------------- | ----------------------------------------------- | -------------------------------------------------- |
| 解密钥匙：该节点的 age 私钥  | 全部           | `/var/lib/sops-nix/key.txt`                     | `--extra-files`                                    |
| SSH 主机密钥                 | 全部           | `/etc/ssh/ssh_host_*_key{,.pub}`                | `--extra-files`                                    |
| 节点口令                     | 全部           | `/etc/rancher/node/password`                    | `--extra-files`                                    |
| etcd、CA、加密密钥           | `sakamoto-k8s` | `/var/lib/rancher/k3s/server`                   | `--extra-files`                                    |
| Longhorn 数据盘              | `sakamoto-k8s` | `/mnt/lima-longhorn`                            | Lima 附加盘，装机时不接触                          |
| Longhorn 与 OpenEBS 本地数据 | `homelab-1`    | `/mnt/lima-longhorn`、`/var/mnt/local-hostpath` | 与系统同盘，整盘重装会擦掉：装机前打包，装好后恢复 |

- k3s 在集群里为每个节点存一个 `<节点名>.node-password.k3s` Secret，口令不匹配会拒绝同名节点加入，所以 `/etc/rancher/node/password` 必须带过去
- `--extra-files <目录>` 把目录原样复制到新系统根目录，目录结构就是目标路径，只在安装时单向复制一次
- age 私钥丢了不丢数据：密文同时写给了管理员公钥，换一把新的、`sops updatekeys`、刷新 `secrets` 输入即可
- `homelab-1` 的 SSH 与 `node/password` 同理；它的本地数据体量大，经 PVE 上的临时卷中转（GNU tar `--sparse`），不进随装目录

## 重装一台节点

1. **drain**：`kubectl drain <节点> --ignore-daemonsets --delete-emptydir-data`。控制面重装期间集群没有 API，worker 上已有的 Pod 继续运行，但不能调度、不能变更，开始前确认 Flux 没有进行中的变更
2. **回滚点**，两条路二选一：
   - Lima：节点停机后，在宿主上用 `cp -c`（APFS 克隆，瞬间完成、几乎不占空间）克隆实例目录里的 `diffdisk`、`datadisk` 与 `lima.yaml`；`sakamoto-k8s` 的 Longhorn 数据盘（`~/.lima/_disks/longhorn/datadisk`）同样克隆
   - PVE：先 `qm shutdown <vmid>`，关机状态下 `qm snapshot <vmid> <名字>`，再 `qm start`。运行中快照会经 guest agent 冻结文件系统，Longhorn 卷的副本在同一台机器的根分区上，冻结顺序不对就互相等待，整机写入卡死
3. **准备随装目录**：按上表建目录，目录结构即目标路径：
   ```bash
   EXTRA=$(mktemp -d)
   # 随装目录经 tar -p 拷贝，每层目录的权限会覆盖目标系统：系统目录用 755，只有放密钥的末级目录用 700
   install -d -m 700 "$EXTRA/var/lib/sops-nix"
   install -d -m 755 "$EXTRA/etc/ssh" "$EXTRA/etc/rancher/node"
   install -m 600 ~/k8s-<节点>-age.txt "$EXTRA/var/lib/sops-nix/key.txt"
   # SSH 主机密钥与 /etc/rancher/node/password：从旧系统取（sudo cat）
   ```
4. **nixos-anywhere 两阶段**，只用这两个配方（在 `nix develop` 里），不要手写 nixos-anywhere 参数：
   ```bash
   # 阶段一：kexec，磁盘不动。安装环境版本、架构、-c 都在配方里；之后若卡在重连就 Ctrl-C
   just anywhere::kexec <节点> <节点 IP>
   # 确认盘与网卡再继续（见下）
   # 阶段二：先把主机声明的 substituters 以覆盖语义写进安装环境（icache 在前），再 disko、install、reboot
   just anywhere::install <节点> <节点 IP> "$EXTRA"
   rm -r "$EXTRA"
   ```
   为什么要配方：nixos-anywhere 自己传 substituters 时只会 `extra-` 追加到末尾，icache 与原站同级，永远轮不到；安装环境太旧时 disko 等不到分区链接（见 `hosts/vps/vps-cc/README.md`）。见 `utils/script/just/anywhere-install`
   阶段一之后核对：`lsblk` 里要抹的盘是 `disko.device` 那块、没有别的盘混入；`ip -br link` 里的 MAC 与 `network.nix` 一致。**这一步之后、disko 之前，重启会回到原系统。**
5. **换上新的 Lima 实例声明**（仅 Lima 节点，见下一节；宿主的 socket_vmnet 须已生效，见「宿主的 socket_vmnet」）
6. **验证**：`nixos-version`、`systemctl is-system-running`、`ip -br a` 里 `eth0`/`eth1`/VLAN 子接口 `eth1.50` 都在且 `eth1` 拿到保留地址、`systemctl status k3s`、`kubectl get node`
7. **首次 `just deploy <节点>`**，不改任何配置：nixos-anywhere 装的那一代没有 deploy-rs 的激活器，不先部署一次，之后配置变坏时无法自动回滚
8. **uncordon**：`kubectl uncordon <节点>`，核对 Longhorn 副本重建完成

### 控制面的额外要点

- 取 `/var/lib/rancher/k3s/server` 前，**不带数据盘**启动原系统：Lima 里先 `limactl stop`，再把 `~/.lima/<节点>/lima.yaml` 临时换成去掉 `additionalDisks` 的普通文件（先 `cp` 一份到别处，`rm` 掉软链，再放回编辑过的副本）后启动，用 `sudo tar` 打包 server 目录并校验；打完删掉这个普通文件，`just deploy <宿主>` 重新链回声明
- 装机时 disko 绝不能看到数据盘：Lima 实例此时仍不挂 `longhorn` 盘，装完、换上声明的 `lima.yaml` 后再挂
- `k3s` 的 server 配置不含令牌：令牌在恢复的 server 目录里；`secrets` 仓库里的 `k3s-token` 只为灾难恢复保存
- k3s 版本不低于集群当前版本：k3s 不支持降级 server

## 更新 Lima 实例配置

实例声明由宿主的 Home Manager 生成：`~/.lima/<节点>/lima.yaml` 是指向 Nix store 的只读符号链接，内容来自 `system.build.limaConfig`。改 `hosts/k8s/lima.nix` 或节点的 `shelken.lima.*` 后：

```bash
just deploy <宿主>                              # 宿主的 Home Manager 换上新的 lima.yaml；agent 不会动运行中的虚拟机
ssh <宿主> 'limactl stop <节点>'                 # 不强停；失败再 --force，并 limactl disk unlock longhorn
ssh <宿主> 'limactl start --tty=false <节点>'    # 或等宿主的自启动 agent；配置在下次启动时生效
```

实例名与节点名相同。`images` 只在新建实例时用，已装好的实例不受影响。`lima.yaml` 只读：`limactl edit` 之类会改配置的命令会被拒，改配置只改 Nix

`limactl start` 用宿主上 Lima 自己生成的密钥（`~/.lima/_config/user`）登录 guest 确认就绪，对应的公钥记在 `vars.limaUserKeys`。删掉 `~/.lima`、重装 Lima 或换宿主后密钥会重新生成：把新的 `user.pub` 写进 `vars.limaUserKeys`，再 `just deploy <节点>`。没更新时只是 `limactl start` 等 SSH 超时、`limactl shell` 不可用，虚拟机与节点照常运行

## 宿主的 socket_vmnet

桥接网卡走 Lima 的非托管模式：`limaConfig` 里是 `socket: /var/run/socket_vmnet.bridged.en0`，socket 由宿主（`sakamoto`、`yuuko`）上 `modules/features/homelab/lima-host/` 的 launchd 守护进程提供。Lima 托管模式要求二进制整条路径归 root、组不可写，Nix store 满足不了

- **生效顺序**：先让宿主的 darwin 配置生效，再换上新的 `lima.yaml`；socket 不存在时 `limactl start` 失败。确认：`ls -l /var/run/socket_vmnet.bridged.en0` 是 socket（`s` 开头），`sudo launchctl print system/io.github.lima-vm.socket_vmnet.bridged.en0` 在运行
- 节点切换完成后，宿主上旧的手工配置可以删除：
  ```bash
  sudo rm -r /opt/socket_vmnet
  sudo rm /etc/sudoers.d/lima
  $EDITOR ~/.lima/_config/networks.yaml   # 删掉 networks 下的 bridged 段
  ```
- 改桥接网卡：改 `vars/default.nix` 里的 `socketVmnet.interface`，宿主与 `limaConfig` 一起变

## 整集群关机与开机

顺序：PVE worker → Lima worker → 控制面；开机反过来

直接 `qm shutdown` / `limactl stop`，不先停 k3s、不强停、不 drain。原因：先停 k3s 再断电，会在卷仍挂载时杀掉 Longhorn 引擎，造成脏盘（2026-08-01 事故）

## kubeconfig

只在控制面重建、CA 变化时需要：

```bash
ssh root@sakamoto-k8s cat /etc/rancher/k3s/k3s.yaml | sed 's#https://127.0.0.1:6443#https://192.168.6.80:6443#' > ~/.kube/home-ops.yaml && chmod 600 ~/.kube/home-ops.yaml
```

## 日常

- 更新：`just k8s::deploy [节点...]`，不带参数部署全部。agent 在前、控制面最后，每台健康（k3s 在运行、系统不是 degraded、kubelet healthz 为 ok）后再继续，否则停下。单台底层是 `just deploy <节点>`（deploy-rs，30 秒内新 SSH 连不上自动回滚；构建在节点上；每台输一次 sudo 密码）
- k3s 升级：`k3s-node` 里的 `package` 写死了 minor，升 minor 要有意修改；先 `sakamoto-k8s` 后 worker
- `homelab-1` 的内核固定在 6.12：原因与期限见 `k3s-nvidia-vgpu/README.md`
- 加节点：secrets 仓库建 age 密钥、`network.nix`、密文；`hosts/k8s/<节点>/`；`hosts/default.nix` 加一条
