# vps-cc：Ubuntu → NixOS 切换手册

美国 KVM VPS（2 核、1.9G 内存、120G 单盘、BIOS、静态网络、没有 DHCP），原先是 Ubuntu，由 home-ops 的 ansible 与 compose 管理。用 nixos-anywhere + disko 整盘换成本仓库的 `vps-cc`

**切换必须本人在场，每个阶段由你确认后再继续。**

## 组成

- `default.nix`：真机特有的部分，主机名与静态网络；网络参数来自私有 `secrets` 仓库的 `hosts/vps-cc/network.nix`（明文，求值期读取）
- `../common.nix`：与演练机 `vps-test` 共用的配置：BIOS + ext4 分区、sops 口令、sysctl、防火墙、tailscale、docker、NTP、DNS
- `docs/adr/0005-server-role-and-core-baseline.md`：为什么是 `server` 角色与系统层 sops
- 口令哈希在 `secrets` 仓库的 `sops/secrets/hosts/vps-cc.yaml`，只有管理员和 vps-cc 自己的 age 密钥能解
- 不用 nixos-facter：真机实测是标准 qemu 虚拟机（virtio 网卡与磁盘），驱动由 nixpkgs 的 `qemu-guest.nix` 提供，见 `../common.nix`；facter 报告含序列号与 MAC，仓库是公开的，不提交

## 演练（vps-test）

在 Lima 的 qemu 里跑一台对齐 VPS 的机器（x86_64、BIOS、2 核、2GiB），用同一份 `common.nix`。软件模拟很慢，一次完整流程约 20 分钟

```bash
just lima-vps-up                                  # qemu 由 nix 临时提供
P=$(just lima-vps-port); KEY=~/.lima/_config/user

# 安装时放进新系统的文件：age 私钥（与真机同一把，顺带演练交付方式）
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix"
install -m 600 <vps-cc 的 age 私钥文件> "$EXTRA/var/lib/sops-nix/key.txt"

KEXEC=$(just kexec-cache x86_64 nixos-26.05)      # 必须 26.05，见下表
# --build-on local：在 Mac 上经 linux-builder 构建 x86_64 系统；真机只有 2GiB 内存，不要在安装环境里构建
# 阶段一：kexec。完成后 nixos-anywhere 会去连 Mac 自己的 22 端口，卡住，超时即可（Lima 只转发了 $P）
timeout 200 nixos-anywhere -f .#vps-test --target-host root@127.0.0.1 --build-on local --ssh-port $P -i $KEY \
  --kexec "$KEXEC" --kexec-extra-flags '-c' --phases kexec
# 阶段二：分区、安装、重启
nixos-anywhere -f .#vps-test --target-host root@127.0.0.1 --build-on local --ssh-port $P -i $KEY \
  --phases disko,install,reboot --extra-files "$EXTRA"
rm -r "$EXTRA"

# 更新：vps-test 在 Lima 里没有可直连的地址，用 --hostname 指定
deploy --skip-checks .#vps-test --hostname 127.0.0.1 --ssh-opts "-p $P -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
limactl delete --force nixos-anywhere-vps
```

### 演练验收结果

| 项                                                                        | 结果                                                                               |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| BIOS + GPT（1M EF02 + ext4）+ GRUB 能引导                                 | 通过，`grub-install` 为 i386-pc，根分区在 `/dev/vda2`                              |
| 静态 IP、网关、MTU 1400，重启后不丢                                       | 通过                                                                               |
| sshd 监听 60223，仅密钥登录，root 与 shelken 都能登录，密码登录被拒       | 通过                                                                               |
| 口令哈希由 sops 在开机时解到 `/run/secrets-for-users`，写入 `/etc/shadow` | 哈希已写入（`$y$`）；**口令本身是否正确没有测，切换后由你在 VNC 或 `sudo` 时验证** |
| zramSwap、BBR、inotify、journald 200M                                     | 通过                                                                               |
| 防火墙放行清单与 `common.nix` 一致                                        | 通过                                                                               |
| docker 守护进程启动、晚于 tailscaled、能拉镜像                            | 通过                                                                               |
| deploy-rs 推送更新，配置把 SSH 堵死后自动回滚                             | 通过，前提见下表第 5 行                                                            |

没有在演练里测：compose 业务容器、crowdsec-firewall-bouncer 与 NixOS 防火墙的配合、tailscale 登录、真实 KVM 下的 kexec

### 演练里遇到的问题

| 现象                                                                      | 原因                                                                                                                                     | 处理                                                                                   |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| kexec 报 `PEFILE: Unsigned PE binary`                                     | Ubuntu 内核拒绝 `kexec_file_load` 加载未签名内核                                                                                         | `--kexec-extra-flags '-c'` 走旧的 `kexec_load`                                         |
| disko 报 `/dev/disk/by-partlabel/disk-main-root does not exist`，每次必现 | disko 脚本用 nixpkgs 的 systemd 262 的 `udevadm settle`，而默认 kexec 安装环境是 25.05（systemd 257），settle 提前返回，符号链接还没出现 | 用 `nixos-26.05` 的 kexec 安装环境：`just kexec-cache x86_64 nixos-26.05`              |
| 装好后 `/etc/resolv.conf` 只有 `127.0.0.1`，整机解析不了域名              | openresolv 默认只写本机解析器；而 127.0.0.1 要等 docker 里的 dnsmasq 起来才有人应答，首次拉镜像就死锁                                    | `networking.resolvconf.extraConfig = "resolv_conf_local_only=NO"`（已在 `common.nix`） |
| 第一次 `deploy` 后配置变坏，自动回滚报 `No such file or directory`        | nixos-anywhere 装的那一代没有 deploy-rs 的激活器，回滚找不到目标                                                                         | 装好后先用**不改任何配置**的 `just deploy vps-cc` 部署一次，再做真实改动               |
| `deploy` 时「Connection reset by peer」                                   | 防火墙规则重载的瞬间，慢速模拟让 SSH 等待连接被拒；真机上这个窗口只有毫秒                                                                | 仅演练环境的现象；真机若遇到，重跑一次                                                 |
| kexec 之后 nixos-anywhere 重连默认的 22 端口                              | 安装环境的 sshd 在 22，旧系统在 60223                                                                                                    | 真机上正好；演练里 Lima 只转发了一个端口，所以卡住                                     |

## 切换（真机）

每一步先停下确认。命令里的 `vps-cc` 是你 `~/.ssh/config` 里的别名（端口 60223）

### 0. 准备

```bash
# 备份业务数据（280MB）
mkdir -p ~/vps-cc-backup && chmod 700 ~/vps-cc-backup
ssh vps-cc 'tar -C /data -czf - docker' > ~/vps-cc-backup/data-docker.tgz
tar -tzf ~/vps-cc-backup/data-docker.tgz | head -3

# 看一眼最近一次 kopia 快照时间（例如 kopia 的 Web 界面，或 docker exec kopia 里列快照）
```

- [ ] 确认能登录服务商网页 VNC 控制台，并知道 root 口令在 1Password 的位置
- [ ] 确认 `secrets` 仓库已推送，`nix flake metadata` 里的 `secrets` 是含 `hosts/vps-cc/network.nix` 的那一版
- [ ] `nix build .#nixosConfigurations.vps-cc.config.system.build.toplevel` 通过

安装时一起带过去的文件（身份与密钥，**不进 git**）：

```bash
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix" "$EXTRA/var/lib/tailscale" "$EXTRA/etc/ssh"
install -m 600 <vps-cc 的 age 私钥文件> "$EXTRA/var/lib/sops-nix/key.txt"
# tailscale 节点身份：保留节点名与 tailnet 地址
ssh vps-cc 'cat /var/lib/tailscale/tailscaled.state' > "$EXTRA/var/lib/tailscale/tailscaled.state"
# SSH 主机密钥：保留，避免所有客户端报主机密钥变更
for k in ed25519 rsa; do
  ssh vps-cc "cat /etc/ssh/ssh_host_${k}_key" > "$EXTRA/etc/ssh/ssh_host_${k}_key"
  ssh vps-cc "cat /etc/ssh/ssh_host_${k}_key.pub" > "$EXTRA/etc/ssh/ssh_host_${k}_key.pub"
done
chmod 600 "$EXTRA"/var/lib/tailscale/* "$EXTRA"/etc/ssh/*_key
```

### 1. kexec（磁盘不动，可随时回头）

```bash
KEXEC=$(just kexec-cache x86_64 nixos-26.05)
nixos-anywhere -f .#vps-cc --target-host root@vps-cc --build-on local --ssh-port 60223 \
  --kexec "$KEXEC" --kexec-extra-flags '-c' --phases kexec
```

之后机器在内存里的 NixOS 安装环境，sshd 在 **22** 端口。若 nixos-anywhere 卡在重连，Ctrl-C，直接做下一步。**这一步之后、disko 之前的任何时候，重启（VNC 控制台强制重启）都会回到原来的 Ubuntu。**

### 2. 核对

```bash
ssh -p 22 root@vps-cc 'ls /sys/firmware/efi 2>&1; lsblk -o NAME,SIZE,TYPE,FSTYPE; ip -br a; ip link show eth0 | grep -o "mtu [0-9]*"; ip r'
```

- [ ] 没有 `/sys/firmware/efi`（BIOS），盘是 `/dev/vda`，120G
- [ ] IPv4、三个 IPv6 地址、网关、MTU 1400 与 `secrets` 仓库里的 `network.nix` 一致
- [ ] 数据已备份、`$EXTRA` 已备齐

### 3. 分区、安装、重启（这一步抹盘）

```bash
nixos-anywhere -f .#vps-cc --target-host root@vps-cc --build-on local --ssh-port 22 \
  --phases disko,install,reboot --extra-files "$EXTRA"
rm -r "$EXTRA"
```

### 4. 验证系统

```bash
ssh vps-cc 'nixos-version; findmnt -no SOURCE,FSTYPE /; ip -br a show eth0; ip link show eth0 | grep -o "mtu [0-9]*"; tailscale status | head -3; systemctl is-system-running'
ssh vps-cc 'stat -c "%U %a %n" /var/lib/sops-nix/key.txt /var/lib/tailscale/tailscaled.state'   # root 600
```

- [ ] 用原来的别名（端口 60223）能登录，没有主机密钥警告
- [ ] `tailscale status` 里还是原来的节点名与地址
- [ ] 你自己在机器上执行一次 `sudo -k true`，确认新口令正确

连不上时：用 VNC 控制台以 root 登录（口令在 1Password），看 `ip a`、`journalctl -b -u network-addresses-eth0 -u sshd`。

### 5. 先做一次「不改配置」的 deploy

```bash
just deploy vps-cc
```

这一步为的是让系统里出现一代由 deploy-rs 激活的配置，之后每次 `deploy` 配置变坏时才能自动回滚。

### 6. 恢复业务

```bash
ssh vps-cc 'tar -C /data -xzf -' < ~/vps-cc-backup/data-docker.tgz
cd ~/Code/active/home-ops && task compose:deploy:vps
```

首次会重新拉取约 3.6GB 镜像。

### 7. 逐项核对

- [ ] `docker ps` 16 个容器都在
- [ ] 对外端口：443（tcp、udp）、8666、3478/udp、10357/udp、5444、60223 能从外部连通
- [ ] tailscale 上绑定的端口（node-exporter、caddy 管理口、kopia、openlist）可从 tailnet 访问
- [ ] crowdsec-firewall-bouncer 在 `INPUT`、`FORWARD`、`DOCKER-USER` 里确实加了规则：`iptables -S | grep -i crowdsec`；若没有，说明它的 iptables 与 NixOS 防火墙不兼容，需要处理
- [ ] derp、hysteria2、anytls 能正常使用；kopia 下一次备份成功
- [ ] 观察一两天，再决定清理 home-ops 的 ansible（那是另一个仓库的单独改动）

## 回滚

| 时机                   | 做法                                                                                                                                                                                                                                                   |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| kexec 之后、disko 之前 | VNC 控制台强制重启，回到 Ubuntu，磁盘没动                                                                                                                                                                                                              |
| disko 之后             | 服务商控制台重装 Ubuntu（地址不变）；加回 SSH 公钥后，home-ops 跑 `ansible/site-others.yml`，把 `~/vps-cc-backup` 里的 `data-docker.tgz` 解回 `/data`，`tailscaled.state` 放回 `/var/lib/tailscale/` 再启动 tailscaled，最后 `task compose:deploy:vps` |

## 日常更新

```bash
just deploy vps-cc
```

deploy-rs 用 root + 密钥推送，激活后新开一个 SSH 连接确认，30 秒内连不上就自动回滚。防火墙、网络、sshd 的改动尤其要依赖它
