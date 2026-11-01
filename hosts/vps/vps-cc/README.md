# vps-cc：Ubuntu → NixOS 切换手册

美国 KVM VPS（2 核、1.9G 内存、120G 单盘、BIOS、静态网络、没有 DHCP），原先是 Ubuntu，由 home-ops 的 ansible 与 compose 管理。用 nixos-anywhere + disko 整盘换成本仓库的 `vps-cc`

**切换必须本人在场，每个阶段由你确认后再继续。**

## 组成

- `default.nix`：真机特有的部分，主机名与静态网络；网络参数来自私有 `secrets` 仓库的 `hosts/vps-cc/network.nix`（明文，求值期读取）
- `../common.nix`：与演练机 `vps-test` 共用的配置：BIOS + ext4 分区、sops 口令、sysctl、防火墙、tailscale、docker、NTP、DNS
- `docs/adr/0005-server-role-and-core-baseline.md`：为什么是 `server` 角色与系统层 sops
- 口令哈希在 `secrets` 仓库的 `sops/secrets/hosts/vps-cc.yaml`，只有管理员和 vps-cc 自己的 age 密钥能解
- 不用 nixos-facter：虚拟机的社区做法是导入 nixpkgs 的 `qemu-guest.nix`（官方 nixos-anywhere-examples 对 KVM 云主机同样如此），真机实测是标准 qemu 虚拟机（virtio 网卡与磁盘）；facter 或 `hardware-configuration.nix` 留给以后的物理机，见 `../common.nix`
- `default.nix` 里还对网卡设了 `accept_ra = 0`、`autoconf = 0`：服务商的路由器会发路由通告，内核据此生成自动 IPv6 地址并排在静态地址之前，监听通配地址的 UDP 服务（hysteria2、derp 的 STUN）回包会用错误的源地址，原因与处理见 `default.nix` 的注释

## 要带过去的三类状态

装机会抹掉整块盘。不在 Nix 配置里、又在旧盘上的东西，都要自己带过去，区别只在「什么时候要」：

| 类       | 是什么                           | 什么时候要                     | 怎么带               |
| -------- | -------------------------------- | ------------------------------ | -------------------- |
| 业务数据 | `/data/docker`                   | 容器启动前，装好后             | 打包备份，装好后恢复 |
| 机器身份 | `tailscaled.state`、SSH 主机密钥 | 开机瞬间：服务一启动就读       | `--extra-files`      |
| 解密钥匙 | 该主机的 age 私钥                | 开机瞬间：系统激活时解口令哈希 | `--extra-files`      |

`--extra-files <目录>` 把本机目录的内容原样复制到新系统的根目录，发生在 install 阶段、第一次开机之前。目录结构就是目标路径：`<目录>/var/lib/sops-nix/key.txt` 变成 `/var/lib/sops-nix/key.txt`，文件默认属主 root。它只在安装时单向复制一次，不是备份，也不是同步。

- 为什么不能装好后再补：tailscaled 与 sshd 启动时就读身份文件，缺了会生成新的。tailscale 会注册成新节点、地址变化；SSH 客户端会报主机密钥变更
- 其余机密都走 sops 加密交付。只有解开 sops 的那把钥匙没法再用 sops 交付，只能带过去，这是官方文档里 `--extra-files` 的典型用法
- age 私钥丢了不丢数据：密文同时写给了管理员公钥，换一把新的、`sops updatekeys`、刷新 `secrets` 输入，再装即可，不需要另存
- 这份清单没有声明在 Nix 配置里：tailscale 与 SSH 主机密钥的路径靠 nixpkgs 默认值，见 nix-config #183

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
| deploy-rs 推送更新，配置把 SSH 堵死后自动回滚                             | 通过，前提见下表「第一次 `deploy` 后配置变坏」一行                                 |

没有在演练里测：compose 业务容器、crowdsec-firewall-bouncer 与 NixOS 防火墙的配合、tailscale 登录、真实 KVM 下的 kexec

### 演练里遇到的问题

| 现象                                                                      | 原因                                                                                                                                     | 处理                                                                                                                                                                                                         |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| kexec 报 `PEFILE: Unsigned PE binary`                                     | Ubuntu 内核拒绝 `kexec_file_load` 加载未签名内核                                                                                         | `--kexec-extra-flags '-c'` 走旧的 `kexec_load`                                                                                                                                                               |
| disko 报 `/dev/disk/by-partlabel/disk-main-root does not exist`，每次必现 | disko 脚本用 nixpkgs 的 systemd 262 的 `udevadm settle`，而默认 kexec 安装环境是 25.05（systemd 257），settle 提前返回，符号链接还没出现 | 用 `nixos-26.05` 的 kexec 安装环境：`just kexec-cache x86_64 nixos-26.05`。选版本前用 `nix eval --raw .#nixosConfigurations.<主机>.config.systemd.package.version` 查 flake 的 systemd，安装环境取同一发布线 |
| 装好后 `/etc/resolv.conf` 只有 `127.0.0.1`，整机解析不了域名              | openresolv 默认只写本机解析器；而 127.0.0.1 要等 docker 里的 dnsmasq 起来才有人应答，首次拉镜像就死锁                                    | `networking.resolvconf.extraConfig = "resolv_conf_local_only=NO"`（已在 `common.nix`）                                                                                                                       |
| 第一次 `deploy` 后配置变坏，自动回滚报 `No such file or directory`        | nixos-anywhere 装的那一代没有 deploy-rs 的激活器，回滚找不到目标                                                                         | 装好后先用**不改任何配置**的 `just deploy vps-cc` 部署一次，再做真实改动                                                                                                                                     |
| `deploy` 时「Connection reset by peer」                                   | 防火墙规则重载的瞬间，慢速模拟让 SSH 等待连接被拒；真机上这个窗口只有毫秒                                                                | 仅演练环境的现象；真机若遇到，重跑一次                                                                                                                                                                       |
| kexec 之后 nixos-anywhere 重连默认的 22 端口                              | 安装环境的 sshd 在 22，旧系统在 60223                                                                                                    | 真机上正好；演练里 Lima 只转发了一个端口，所以卡住                                                                                                                                                           |

## 切换（真机）

每一步先停下确认。命令里的 `vps-cc` 是你 `~/.ssh/specific` 里的别名（端口 60223）

### 0. 准备

```bash
# 备份业务数据（280MB）
mkdir -p ~/vps-cc-backup && chmod 700 ~/vps-cc-backup
ssh vps-cc 'tar -C /data -czf - docker' > ~/vps-cc-backup/data-docker.tgz
tar -tzf ~/vps-cc-backup/data-docker.tgz | head -3

# 看一眼最近一次 kopia 快照时间（例如 kopia 的 Web 界面，或 docker exec kopia 里列快照）
```

- [ ] 确认能登录服务商网页 VNC 控制台。装机后 root 的口令是 `secrets` 里哈希对应的**新口令**，不是服务商给的旧口令，先确认你记得它
- [ ] 确认 `secrets` 仓库已推送，`nix flake metadata` 里的 `secrets` 是含 `hosts/vps-cc/network.nix` 的那一版
- [ ] `nix build .#nixosConfigurations.vps-cc.config.system.build.toplevel` 通过

安装时一起带过去的文件（身份与密钥，**不进 git**）：

```bash
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix" "$EXTRA/var/lib/tailscale"
# etc/ssh 必须 755：目录权限会原样带到新系统，700 会让普通用户无法用公钥登录
install -d -m 755 "$EXTRA/etc/ssh"
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

连不上时：用 VNC 控制台以 root 和新口令登录，看 `ip a`、`journalctl -b -u network-addresses-eth0 -u sshd`。

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
- [ ] IPv6：网卡上只有静态地址（`accept_ra`、`autoconf` 为 0），`ip -6 route get <公网 IPv6>` 的 `src` 是固定地址；独立客户端经固定 IPv6 能连上 hysteria2（见 nix-config #182）
- [ ] 日志驱动：NixOS 默认 `journald`，不接受 compose `logging.options` 里的 `max-size`、`max-file`；接管前对比 `docker info` 的日志驱动与 compose 的 `logging`（见 home-ops #1728）
- [ ] 观察一两天，再决定清理 home-ops 的 ansible（那是另一个仓库的单独改动）
- [ ] 稳定后删除本机的随装目录（含 age 私钥、SSH 主机私钥、tailscale 状态）；数据包留到确认不会回滚

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

部署前 Mac 上的 `linux-builder` 必须在运行，x86_64-linux 的构建靠它。构建之后再改已跟踪文件，会让一串系统组装层的小派生重建（nix-config #181）。想知道会不会重建，用 `nix build <路径> --dry-run`；判断某个工具会不会在本机编译，先 `nix path-info --store https://cache.nixos.org <路径>` 查缓存，`--dry-run` 只列清单、不下载。

## 切换后发现的问题

各自的 issue：

- 自动 IPv6 地址导致 UDP 回包源地址错误：nix-config #182（已关闭，修复在 `default.nix`）
- compose 的 `logging.options` 与 NixOS 默认的 journald 日志驱动不兼容：home-ops #1728
- 构建的系统与实际部署的系统不是同一个：nix-config #181
- deploy-rs 激活器要从源码编译：nix-config #184（已关闭）；本机磁盘紧张：nix-config #185
- 执行记录与第 7 步核对清单：nix-config #183
