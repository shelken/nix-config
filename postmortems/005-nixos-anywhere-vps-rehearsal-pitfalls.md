# nixos-anywhere 接管 x86_64 BIOS VPS 的演练：五个会在真机出事的坑

**日期**: 2026-10-31
**影响**: 没有影响真机。演练机（Lima + qemu，对齐 VPS 规格）暴露了五个问题，其中前三个若直接上真机会让安装失败、整机解析不了域名，或失去回滚能力
**发现人**: 用 x86_64 BIOS 演练机完整走一遍 kexec、disko、install、reboot、deploy-rs 时发现，修复见 PR #178

## 问题

- 之前的演练只在 aarch64 + UEFI 的 Lima 里做过，与真机（x86_64、BIOS、静态网络、2G 内存、Ubuntu 内核）差别大，沿用其结论会漏掉整类问题
- 交接文档说 `just nixos-anywhere` 已存在，实际上该配方在演练提交里被删掉，文档仍在引用
- 下面五个问题只有换成对齐真机的演练机才会出现

## 现象

1. kexec 阶段失败

   ```text
   PEFILE: Unsigned PE binary
   Kexec failed
   ```

2. disko 阶段每次必现，装机后磁盘分区其实已建好

   ```text
   + mkfs.ext4 /dev/disk/by-partlabel/disk-main-root
   The file /dev/disk/by-partlabel/disk-main-root does not exist and no size was specified.
   ```

3. 装好后 `/etc/resolv.conf` 只有 `nameserver 127.0.0.1`，`getent hosts cache.nixos.org` 无输出，而 `resolvconf -l` 里两个服务器都在
4. 第一次 `deploy` 部署会把 SSH 堵死的配置后，自动回滚失败

   ```text
   There was an error de-activating after an error was encountered:
   Failed to run Nix reactivate last generation command: No such file or directory
   ```

5. kexec 阶段实际已成功，但 nixos-anywhere 卡住不退出；`net.ipv6.conf.eth0.accept_ra` 仍是 1，尽管 `all` 与 `default` 都设了 0

## 根因

- 错误假设：「实机的 kexec、分区、更新流程和 aarch64 + UEFI 的演练一样」。实际约束：
  1. Ubuntu 内核拒绝 `kexec_file_load` 加载未签名内核，必须走旧的 `kexec_load`
  2. 默认 kexec 安装环境是 25.05（systemd 257），disko 脚本用的是 flake 里 nixpkgs 的 systemd 262 的 `udevadm`，版本不一致时 `udevadm settle` 提前返回，`by-partlabel` 链接还没出现就开始 mkfs。在安装环境里手动跑同样的 sgdisk、partprobe、settle 序列，链接立即出现
  3. openresolv 的 `resolv_conf_local_only` 默认是 YES，只要有本机解析器就只写本机的；而 `127.0.0.1` 要等 docker 里的 dnsmasq 起来才应答，起来之前整机解析不了域名，首次拉镜像还需要解析，形成死锁
  4. nixos-anywhere 装的那一代没有 deploy-rs 的激活器，回滚要重新激活「上一代」，找不到
  5. nixos-anywhere 在 kexec 之后重连默认的 22 端口，不沿用 `--ssh-port`；Lima 只转发一个本机端口，22 连到的是 Mac 自己的 sshd。`accept_ra` 是接口级设置，接口在 `sysctl` 服务运行之前就已建立，`default` 只对之后新建的接口生效
- 缺失检查点：没有在第一次真机动作前，用对齐规格的机器把整条链路走完；也没有核对交接文档里「已有」的配方是否真的在仓库里

## 修复

- kexec 加 `--kexec-extra-flags '-c'`
- 安装环境用 `nixos-26.05`（systemd 260）：`just kexec-cache x86_64 nixos-26.05`
- `hosts/vps/common.nix` 设 `networking.resolvconf.extraConfig = "resolv_conf_local_only=NO"`，并去掉没有生效的 `accept_ra` sysctl
- 补回 `just nixos-anywhere` 配方，默认 `--build-on local`
- 手册 `hosts/vps/vps-cc/README.md` 规定：装好后先做一次不改配置的 `just deploy vps-cc`，之后再做真实改动
- 演练里卡住的重连用 `timeout` 包起来，直接跑下一阶段；真机上安装环境的 sshd 正好在 22

## 预防

- 接管真机前，先用规格对齐的演练机完整走完 kexec、disko、install、reboot、deploy，规格至少包括架构、固件（BIOS 或 UEFI）、网络是否静态、内存
- 用 nixos-anywhere 前先 `nix eval` 出 flake 的 systemd 版本，kexec 安装环境选不低于它的 nixos-images 发布：`nix eval --raw .#nixosConfigurations.<主机>.config.systemd.package.version`，对照 `gh api repos/nix-community/nixos-images/releases`
- 任何会让本机解析器（127.0.0.1）排在 `networking.nameservers` 第一位的配置，同时设 `resolv_conf_local_only=NO`，并在演练机里执行 `cat /etc/resolv.conf` 与 `getent hosts cache.nixos.org`
- 把 deploy-rs 加到刚由 nixos-anywhere 装好的主机时，第一次部署必须是不改配置的版本，确认 `Deployment confirmed.` 之后才允许部署防火墙、网络、sshd 的改动
- 交接文档里写「已有」的命令或配方，用 `just --list` 或 `grep` 核实，再往下用
- 要靠 `sysctl` 控制接口级行为（如 `accept_ra`）时，在演练机里读 `sysctl net.ipv6.conf.<接口>.accept_ra` 确认，不要只看 `all` 与 `default`
