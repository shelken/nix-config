# VPS 业务容器：Compose → OCI 容器

`vps-cc` 的业务容器原先由 home-ops 的 `docker compose` 部署，现在改由本仓库的 `virtualisation.oci-containers` 声明（继续用 Docker backend）。
代码在 `hosts/vps/vps-cc/apps/`，一个容器一个文件。当前纳管三个典型服务：

| 服务            | 覆盖的情况                                         |
| --------------- | -------------------------------------------------- |
| `node-exporter` | 无状态，只读挂载宿主机目录，端口只发布到 Tailscale |
| `openlist`      | 有状态，业务数据目录 + HTTP 健康检查               |
| `kopia`         | 依赖型，等 openlist 健康后启动，密钥与配置文件多   |

声明式覆盖到的部分：

| 事项          | 现在的做法                                                                  |
| ------------- | --------------------------------------------------------------------------- |
| 共享网络      | `docker-network-homelab.service` 检查 `homelab`，不存在才按原参数创建       |
| 容器生命周期  | 每个容器一个 `docker-<名>.service`，启动前自动 `docker rm -f` 同名容器      |
| 配置/密钥更新 | sops 模板渲染环境文件，内容变化触发对应容器重建                             |
| 重启意图      | 旧 Compose 的 `restart: always` 由 `Restart=always` + `RestartSec=10s` 承担 |
| 启动依赖      | `kopia` 等 openlist 真的 `healthy` 才启动（`dependsOn` 只管顺序与依赖）     |

## 部署前必须补齐的两处私有输入

这两处都不在公开仓库里，缺任一处求值或激活会失败。

1. `secrets` 仓库的 `hosts/vps-cc/network.nix` 增加 Tailscale 地址（容器端口只发布到这个地址，否则等于把服务放到公网）：

   ```nix
   tailscaleIp = "<vps-cc 的 Tailscale 地址>";
   ```

2. `secrets` 仓库的 `sops/secrets/hosts/vps-cc.yaml` 用 sops 增加以下字段（值取旧 BWS 里的同名变量，迁移期间不轮换）：

   ```yaml
   openlist:
     admin-username: ...
     admin-password: ...
     s3-access-key-id: ...
     s3-secret-access-key: ...
     webdav-username: ...
     webdav-password: ...
   kopia:
     password: ...
     webhook-url: ...
   ```

   `webdav-username` / `webdav-password` 是 kopia 访问 openlist WebDAV 的凭据，旧 Compose 从 `OPENLIST_WEBDAV_*` 注入。

## 切换步骤

1. 先在 home-ops 里删掉这三个服务的 Compose 声明（或至少不再执行 `task compose:deploy:vps`）。
   不这么做的话，`docker compose up` 会按它自己的声明重建同名容器，把 Nix 的容器顶掉。
2. 核对实际卷名：`docker volume ls | grep kopia`。`apps/kopia/default.nix` 里的 `cacheVolume` 按 Compose 项目名推断为 `homelab-compose_kopia_cache`，对不上就改成本机实际值。
   这个卷只放缓存与对账指纹，名字错了不会丢备份数据，但会重新对账一次。
3. 部署：`just deploy vps-cc`。

## 验收

```bash
systemctl status docker-network-homelab.service
systemctl status docker-node-exporter.service docker-openlist.service docker-kopia.service
journalctl -u docker-kopia.service -b          # 等 openlist healthy 的日志、策略对账、server 启动
docker ps --format '{{.Names}}\t{{.Status}}'   # 容器名应与旧的一致
```

外部调用方（Gatus、Prometheus）走 Tailscale 地址的 `9100`、`5244`、`51515`，端口绑定没变就能继续通过。

## 回退

1. 在 home-ops 恢复这三个服务的 Compose 声明。
2. 本仓库回到不含 `hosts/vps/vps-cc/apps` 的提交，再 `just deploy vps-cc`：Nix 侧的容器与网络单元随之删除。
3. `task compose:deploy:vps` 拉起旧容器。

数据目录 `/data/docker/openlist/data`、`/data/docker/kopia/logs`、`/data` 与命名卷都不在切换动作里，回退不需要搬数据；反过来，Nix 配置回退也不会把应用写过的数据退回去。

## 还没纳管的部分

其余服务（caddy、crowdsec、mosdns、dnsmasq、derp、hysteria2、anytls、fluent-bit、dockerproxy、dhp、sub-converter、sbtools-server）仍在 home-ops 的 Compose 里，按同一模式分批迁移；本页只覆盖上表三个。
