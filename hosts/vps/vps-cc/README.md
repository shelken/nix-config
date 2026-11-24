# vps-cc

美国 KVM VPS（2 核、1.9G 内存、120G `/dev/vda`、BIOS、静态网络、MTU 1400、SSH 端口 60223）。通用装机、日常更新与回滚流程见 [VPS 指南](../../../docs/user-guide/05-vps.md)，业务容器声明与维护见 [容器服务](../../../docs/user-guide/06-containers.md)

## 本机参数与密文位置

- 静态网络参数：`secrets` 仓库 `hosts/vps-cc/network.nix`（明文，求值期读取）
- 系统口令与服务机密：`secrets` 仓库 `sops/secrets/hosts/vps-cc.yaml`
- 网卡禁用 IPv6 RA（`accept_ra = 0`、`autoconf = 0`），避免自动地址抢占 UDP 回包源地址（原因见 `default.nix` 注释）

## 业务数据备份与恢复

```bash
# 重装前备份 /data/docker
mkdir -p ~/vps-cc-backup && chmod 700 ~/vps-cc-backup
ssh vps-cc 'tar -C /data -czf - docker' > ~/vps-cc-backup/data-docker.tgz

# 装好系统并完成首次 just deploy vps-cc 后恢复
ssh vps-cc 'tar -C /data -xzf -' < ~/vps-cc-backup/data-docker.tgz
just deploy vps-cc
```

也可在 `home-ops` 从 kopia 快照恢复：`task kopia:list` 选快照，执行 `task kopia:full SNAPSHOT_ID=<id>` 推回 `/data/docker`

## 本机 `--extra-files` 收集与两阶段安装

随装目录权限规则见 [VPS 指南](../../../docs/user-guide/05-vps.md)：

```bash
EXTRA=$(mktemp -d)
install -d -m 700 "$EXTRA/var/lib/sops-nix" "$EXTRA/var/lib/tailscale"
install -d -m 755 "$EXTRA/etc/ssh"
install -m 600 <vps-cc 的 age 私钥文件> "$EXTRA/var/lib/sops-nix/key.txt"
ssh vps-cc 'cat /var/lib/tailscale/tailscaled.state' > "$EXTRA/var/lib/tailscale/tailscaled.state"
for k in ed25519 rsa; do
  ssh vps-cc "cat /etc/ssh/ssh_host_${k}_key" > "$EXTRA/etc/ssh/ssh_host_${k}_key"
  ssh vps-cc "cat /etc/ssh/ssh_host_${k}_key.pub" > "$EXTRA/etc/ssh/ssh_host_${k}_key.pub"
done
chmod 600 "$EXTRA"/var/lib/tailscale/* "$EXTRA"/etc/ssh/*_key
```

备好数据与 `$EXTRA` 后，先用 `tar -tzf ~/vps-cc-backup/data-docker.tgz` 校验备份可读并确认 VNC 控制台可进，再在 `nix develop` 中按 [VPS 指南](../../../docs/user-guide/05-vps.md) 执行两阶段 `nixos-anywhere`：阶段一走原 SSH 端口 `60223`、加 `--build-on local` 与 `--kexec-extra-flags '-c'`；kexec 后登录 22 端口确认 BIOS、`/dev/vda` 及 `network.nix` 地址一致再抹盘；阶段二用 `--ssh-port 22`、`--build-on local` 与 `--extra-files "$EXTRA"`，装完即删除 `$EXTRA`

## 回滚与更新

- `just deploy vps-cc` 默认按 `hosts/default.nix` 的 `remoteBuild = true` 在 VPS 本地构建并激活，30 秒内新 SSH 连不上自动回滚
- 彻底回滚到旧 Ubuntu：服务商控制台重装 Ubuntu 并加回 SSH 公钥，在 `home-ops` 检出迁移前提交 `9cdfe6ef^` 执行 `ansible/site-others.yml`，恢复 `/data/docker` 与 `/var/lib/tailscale/tailscaled.state` 后执行 `task compose:deploy:vps`
