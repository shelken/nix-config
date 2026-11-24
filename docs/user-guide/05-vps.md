# VPS：接管与部署

把一台装着任意 Linux 的 VPS 换成 NixOS 并交给 `deploy-rs` 远程管理。`vps-cc` 切换实录见 [hosts/vps/vps-cc/README.md](../../hosts/vps/vps-cc/README.md)，密钥分层原因见 [ADR 0011](../adr/0011-secret-source-by-consumer.md)

## 加一台新 VPS

### 1. 核对目标机信息

在旧系统执行并记录：

```bash
ls /sys/firmware/efi        # 存在为 uefi，否则为 bios
lsblk -o NAME,SIZE,TYPE     # 系统盘（virtio 多为 /dev/vda）
ip -br a; ip r; ip -6 r     # 网卡名、IP、前缀、网关
ip link show <网卡>         # MTU
```

### 2. 在 `secrets` 仓库准备网络与密钥

1. 新增 `hosts/<主机>/network.nix`（明文网络参数，格式见 `vps-cc`）
2. 执行 `age-keygen -o <主机>-age.txt` 生成主机私钥，妥善留存本地（不入任何仓库）
3. 在 `.sops.yaml` 的通用规则之前添加 `sops/secrets/hosts/<主机>\.yaml$`，接收方写管理员公钥与主机公钥
4. 新建 `sops/secrets/hosts/<主机>.yaml`，写入 `shelken-password-hash` 与 `root-password-hash`（用 `nix shell nixpkgs#mkpasswd -c mkpasswd -m yescrypt` 生成）
5. 推送 `secrets` 后回到本仓库执行 `just upp secrets`

### 3. 写主机配置并注册

1. 复制 [hosts/vps/vps-cc/](../../hosts/vps/vps-cc/) 为 `hosts/vps/<主机>/`，改主机名与 `network.nix` 路径；磁盘选项见 [disko.nix](../../modules/features/system/disko.nix)（使用 `disko` 时硬件配置勿重复声明 `fileSystems`/`swapDevices`；新增第二台 VPS 时把 `hosts/vps/common.nix` 中针对 `vps-cc` 的 sops 路径、端口与防火墙拆回各主机）
2. 在 [hosts/default.nix](../../hosts/default.nix) 登记新主机，在 `~/.ssh/specific` 添加同名 SSH 别名（地址与端口）
3. 执行 `git add hosts/vps/<主机>` 并验证构建：

```bash
nix build .#nixosConfigurations.<主机>.config.system.build.toplevel
```

## 装机

### 准备随装目录（First-boot State）

将开机即需读取的身份与密钥按目标路径放进临时目录 `$EXTRA`（业务数据装好后再恢复）。目录权限会经 `tar -p` 覆盖目标系统：系统上级目录保持 `755`（比如 `etc/ssh`），仅存放密钥的末级目录用 `700`（`var/lib/sops-nix`、`var/lib/tailscale`），私钥文件设为 `600`：

- `/var/lib/sops-nix/key.txt`：主机 age 私钥
- `/var/lib/tailscale/tailscaled.state`：保留原 tailnet 身份（已有节点时）
- `/etc/ssh/ssh_host_*_key` 与 `.pub`：保留 SSH 主机密钥（可选）

### 两阶段安装

配方定义在 [just/anywhere.just](../../just/anywhere.just)，阶段一不碰磁盘，阶段二才抹盘：

```bash
just anywhere::kexec <主机> <目标>                  # 阶段一：kexec 进安装环境，卡在重连时 Ctrl-C
just anywhere::install <主机> <目标> "$EXTRA"      # 阶段二：写 substituters 后 disko、install、reboot
```

### 装好之后

1. 用原 SSH 别名登录，检查 `nixos-version`、网卡地址与 `tailscale status`
2. 立刻执行一次**不改任何配置**的 `just deploy <主机>`（否则首代缺少 deploy-rs 激活器，下次改动出错时自动回滚会失败）
3. 恢复业务数据并启动容器（见 [容器服务](06-containers.md)），确认无误后删除本机 `$EXTRA`

## 日常更新与回滚

```bash
just deploy-diff <主机>             # 查看待部署变更
just plan <主机> deploy             # 查看编译与下载量
just deploy <主机>                  # 远程部署，30 秒内确认失败自动回滚
just deploy <主机> --dry-activate   # 仅演练激活差异
```

- 改动防火墙、网络或 sshd 时不要绕过 `just deploy` 直接跑 `nixos-rebuild`；构建后勿再改已跟踪文件
- kexec 后、抹盘前：在服务商 VNC 控制台强制重启即可回到旧系统
- 抹盘后连不上：通过 VNC 控制台重启在 GRUB 选上一代，或用 root 与 sops 口令登录排查；彻底回退旧系统需重装后恢复备份与 `tailscaled.state`
