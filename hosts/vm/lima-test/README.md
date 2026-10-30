# lima-test：Ubuntu → NixOS 接管演练

用 Lima 起一台 Ubuntu 虚拟机当「已有 Linux 的机器」，再用 nixos-anywhere 把它整盘换成本仓库的 `lima-test` 配置。流程与接管真机/VPS 一致，只是目标 IP 与磁盘名不同

## 组成

- `default.nix`：主机配置，角色 `tui`，导入可选功能 `disko`（`modules/features/nixos/disko.nix`）
- `facter.json`：nixos-facter 硬件报告，安装时生成并提交；不存在时 `default.nix` 用 virtio 兜底内核模块
- `nixos-anywhere-test.yaml`：Lima 模板，声明目标机（Ubuntu 26.04、vz、plain 模式、vzNAT 网卡、root 授权 Lima 密钥）
- `justfile` 里的 `lima-target-up` / `lima-target-ip` / `lima-target-rm` / `nixos-anywhere`

## 安装步骤

在仓库根目录、`nix develop` 的 shell 里执行（devShell 自带 nixos-anywhere）

```bash
# 1. 按模板起目标机（等价于 limactl start hosts/vm/lima-test/nixos-anywhere-test.yaml）
just lima-target-up
IP=$(just lima-target-ip)
KEY=~/.lima/_config/user          # Lima 自己的密钥，模板的 provision 已授权给 root

# 2. 看清楚要抹的是哪块盘：vda 是系统盘，vdb 是 cloud-init 的 cidata，别选错
limactl shell nixos-anywhere-test lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS

# 3. 第一阶段：只做 kexec，把 Ubuntu 换成内存里的 NixOS 安装环境，磁盘不动
just nixos-anywhere lima-test root@$IP -i $KEY --phases kexec
ssh -i $KEY root@$IP 'cat /etc/os-release | head -2; lsblk'   # 应该看到 NixOS，vda 还在

# 4. 采集硬件报告并提交（flake 只看得见 git 跟踪的文件）
ssh -i $KEY root@$IP 'nixos-facter -o /tmp/facter.json || nix run nixpkgs#nixos-facter -- -o /tmp/facter.json'
scp -i $KEY root@$IP:/tmp/facter.json hosts/vm/lima-test/facter.json
git add hosts/vm/lima-test/facter.json

# 5. 安装前在 Mac 上确认 disko 会挂出什么
nix eval .#nixosConfigurations.lima-test.config.fileSystems --apply 'fs: builtins.mapAttrs (_: v: v.device) fs'

# 6. 第二阶段：分区格式化 → 构建安装 → 重启
just nixos-anywhere lima-test root@$IP -i $KEY --phases disko,install,reboot

# 7. 重启后用自己的密钥登录（root 与 shelken 的 authorized_keys 来自 vars 的 mainSshAuthorizedKeys）
ssh root@$IP 'nixos-version; findmnt -t btrfs; swapon'
```

## 预期现象

- 重启后 `limactl shell` 不再可用：NixOS 只授权了你自己的密钥，Lima 的密钥登不进去。这是预期的，虚拟机照常运行，用 `ssh root@$IP` 访问，`limactl stop -f nixos-anywhere-test` 可停
- 要重来：`just lima-target-rm && just lima-target-up`，`facter.json` 可保留复用

## 排障

- **kexec 后 ssh 一直连不上**：先看 Mac 上 `/var/db/dhcpd_leases`，安装环境可能拿到了新 IP，换 IP 后从下一个阶段继续；超过几分钟仍无响应，可能是 vz 下 kexec 不顺，删掉实例改用 qemu 重来：`limactl start --vm-type=qemu --set '.networks=[{"lima":"shared"}]' hosts/vm/lima-test/nixos-anywhere-test.yaml`（vzNAT 只支持 vz，qemu 要换成 socket_vmnet 的 shared 网络，需先装 socket_vmnet）
- **构建**：`just nixos-anywhere` 默认 `--build-on local`，经 linux-builder 在本机构建（先 `linux-builder` 启动它）；想在安装环境的内存里构建，追加 `--build-on remote` 并给演练机更多内存
- **重启后进不了系统**：`limactl start` 的串口日志在 `~/.lima/nixos-anywhere-test/serial*.log`；ESP 里应有 `\EFI\BOOT\BOOTAA64.EFI`

## 日常更新

安装完成后它就是普通的 NixOS 主机，和其他机器一样远程部署：在 `vars/networking.nix` 加一个 `lima-test` 的 ssh 别名，flake 主机表里设 `deploy = { remoteBuild = true; };`，之后 `just deploy lima-test`
