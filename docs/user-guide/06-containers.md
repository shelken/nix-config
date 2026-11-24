# 容器服务

VPS 业务容器通过 `virtualisation.oci-containers` 声明，代码与当前已纳管服务见 [hosts/vps/vps-cc/apps/](../../hosts/vps/vps-cc/apps/)；`sakamoto`（macOS）的 Compose 声明与操作见 [hosts/sakamoto/apps/README.md](../../hosts/sakamoto/apps/README.md)

## 文件落点

- 单主机服务放在 `hosts/vps/vps-cc/apps/<服务>.nix`（含入口脚本或静态配置时建 `<服务>/default.nix`，用 `${./文件名}` 挂载），共享底座与范例参考同目录的 [default.nix](../../hosts/vps/vps-cc/apps/default.nix)、[openlist.nix](../../hosts/vps/vps-cc/apps/openlist.nix) 与 [kopia/default.nix](../../hosts/vps/vps-cc/apps/kopia/default.nix)
- 多主机共用的脚本或策略放 `modules/features/`

## 注入密钥（`sops.templates`）

在 `secrets` 仓库的 `sops/secrets/hosts/<主机>.yaml` 加字段并推送后，回到本仓库执行 `just upp secrets` 更新 `flake.lock`，再在服务文件中用模板渲染 env 文件：

```nix
sops.secrets."openlist/admin-password" = { };
sops.templates."openlist.env" = {
  content = ''
    OPENLIST_ADMIN_PASSWORD=${config.sops.placeholder."openlist/admin-password"}
  '';
  restartUnits = [ "docker-openlist.service" ];
};
virtualisation.oci-containers.containers.openlist.environmentFiles = [
  config.sops.templates."openlist.env".path
];
```

## 必看踩坑

- **端口必须绑地址**：写 `"${address}:<宿主端口>:<容器端口>"` 绑定到 Tailscale 地址（来自 `vars/networking.nix`）；裸写 `5244:80` 会监听 `0.0.0.0` 并经 Docker NAT 绕过防火墙
- **机密只走 `environmentFiles` 或挂载渲染文件**：不要把 `config.sops.placeholder.*` 直接写进 `environment`，容器会收到字面占位符
- **不要传 `--restart`**：`apps/default.nix` 已在 systemd 层统一设 `Restart=always`，`--restart` 会与模块自带的 `--rm` 冲突；也不要在 `ExecStartPre` 里轮询等待依赖，避免拖超时触发 deploy-rs 回滚

## 加一个服务清单

- [ ] 新建 `hosts/vps/vps-cc/apps/<服务>.nix`（或 `<服务>/default.nix`），确认数据目录与 `docker volume ls` 命名卷一致
- [ ] 将新文件加入 [hosts/vps/vps-cc/apps/default.nix](../../hosts/vps/vps-cc/apps/default.nix) 的 `imports` 并执行 `git add`（`apps/default.nix` 显式列举导入，漏登记时求值与部署均会通过但容器不会生效）
- [ ] 配置 `networks = [ "homelab" ]`（需宿主机网络栈时改用 `extraOptions = [ "--network=host" ]` 且不写 `networks`）与端口绑定
- [ ] 非机密放 `environment`，机密走 `sops.templates` 并执行 `just upp secrets`
- [ ] 核对求值：`nix eval .#nixosConfigurations.<主机>.config.system.build.toplevel.drvPath`
- [ ] 部署：`just deploy vps-cc`，验收 `systemctl status docker-<服务>`、`journalctl -u docker-<服务>` 与 tailnet 端口连通
- [ ] 在 home-ops 的 Gatus 规则补探测检查

## 回退到旧 Compose

回退顺序**不能反**：先在本仓库移除该服务声明并执行 `just deploy vps-cc`（systemd 清理阶段会 `docker rm -f` 同名容器），再在 home-ops 历史提交 `9cdfe6ef^` 执行 `task compose:deploy:vps` 拉起旧容器；顺序反了会把刚拉起的新容器删掉

相关：[VPS 接管与部署](05-vps.md)
