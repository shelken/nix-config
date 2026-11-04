# 容器服务

`vps-cc` 上原先由 home-ops 的 docker compose 部署的业务容器，现在由本仓库声明：`virtualisation.oci-containers`，Docker 后端。这一页说明怎么引入一个服务，代码放哪、环境变量与密钥从哪来、网络与端口怎么定、怎么切换与回退

代码在 `hosts/vps/vps-cc/apps/`，VPS 上的业务容器已全部纳管，见文末「当前已纳管的服务」

## 先决定用哪种方式

| 情况                                  | 做法                                                  |
| ------------------------------------- | ----------------------------------------------------- |
| nixpkgs 有对应 module（`services.*`） | 用原生服务，例如 `services.prometheus.exporters.node` |
| 只有容器镜像，依赖关系简单            | 用本页的 `oci-containers`                             |
| 多个服务共享网络、配置与启动顺序      | 先按服务逐个搬，不要为一个服务自写一层 systemd unit   |

原生 module 能覆盖的不要包一层容器声明：包一层只是多一份要维护的镜像与挂载

## 文件组织

```text
hosts/vps/vps-cc/
├── default.nix                主机入口：主机名、静态网络、导入 ./apps
└── apps/
    ├── default.nix            聚合：后端、共享网络、统一重启策略、绑定地址
    ├── node-exporter.nix      服务文件，没有附带文件时
    └── kopia/
        ├── default.nix        服务文件
        ├── entrypoint.sh      随容器挂进去的文件
        └── policy.json
```

| 规则         | 说明                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------ |
| 放置位置     | 只有一台主机用的放 `hosts/<...>/apps/`，多台主机共用才进 `modules/features/`                     |
| 文件粒度     | 一个服务一个文件，文件名就是容器的属性名                                                         |
| 附带文件     | 入口脚本、策略、配置跟服务放同一目录，用 `${./entrypoint.sh}` 挂进容器（`Nix store` 路径，只读） |
| 含机密的配置 | 不落仓库，走 sops 模板，见下一节                                                                 |
| 主机入口     | 新目录只在 `imports` 里加一次，服务文件不再单独导入                                              |

`apps/default.nix` 是三件共用的事：后端固定 `docker`、`homelab` 网络单元、所有容器的重启策略。新服务不重复写这些

## 从 Compose 抄字段

| Compose                       | 这里                                                              |
| ----------------------------- | ----------------------------------------------------------------- |
| `image`                       | `image`，带多架构索引 digest                                      |
| `command` / `entrypoint`      | `cmd` / `entrypoint`                                              |
| `environment`                 | `environment`，只放非机密                                         |
| `env_file`                    | `environmentFiles`，机密走 sops 模板                              |
| `ports`                       | `ports`，必须带地址，见「网络与端口」                             |
| `volumes`                     | `volumes`，命名卷先核对实际名字                                   |
| `networks`                    | `networks`，服务之间用容器名互相解析                              |
| `configs`                     | `volumes`，只读挂 `Nix store` 路径或 sops 模板路径                |
| `hostname` / `container_name` | `hostname` / 容器属性名                                           |
| `healthcheck`                 | `extraOptions`，传 `--health-cmd` 等                              |
| `cap_add`、`privileged` 等    | `capabilities`、`extraOptions`                                    |
| `depends_on`                  | `dependsOn`，只保证顺序与依赖，不等健康就绪                       |
| `restart`                     | 在 `apps/default.nix` 统一给 `Restart=always`，不要用 `--restart` |

三个容易踩的点

- `ports` 写成 `5244:80` 会绑到 `0.0.0.0`，Docker 的端口发布走 NAT、绕过 NixOS 防火墙，等于把服务放到公网
- 模块默认 `Restart=on-failure` 会放走「退出码 0 就退出」，而 `--restart` 与模块默认加的 `--rm` 冲突，所以重启策略只在 systemd 侧配
- 命名卷带 Compose 项目名前缀，`kopia_cache` 实际可能是 `homelab-compose_kopia_cache`，迁移前用 `docker volume ls` 对一下，名字不对会新建一个空卷

## 环境变量与密钥从哪来

| 内容                     | 放哪                                                                            | 例子                                    |
| ------------------------ | ------------------------------------------------------------------------------- | --------------------------------------- |
| 非机密的运行参数         | 容器 `environment`                                                              | `TZ`、`HTTP_PORT`                       |
| 口令、token、Webhook URL | 私有 `secrets` 仓库的 sops 字段，模板渲染成 env 文件，容器读 `environmentFiles` | openlist 的 admin 口令                  |
| 含机密的配置文件         | sops 模板渲染整个文件，再按 `volumes` 挂进容器                                  | kopia 的仓库配置里有 WebDAV 凭据        |
| 主机事实（地址等）       | `vars/networking.nix` 的 `hostAddress` 表                                       | `vps-cc-ts` 的 tailnet 地址             |
| 不含机密的文件           | 跟服务放同一目录，直接挂 `Nix store` 路径                                       | kopia 的 `policy.json`、`entrypoint.sh` |

以一个 token 为例

```nix
sops.secrets."openlist/admin-password" = { };

sops.templates."openlist.env" = {
  content = ''
    OPENLIST_ADMIN_PASSWORD=${config.sops.placeholder."openlist/admin-password"}
  '';
  # env 文件在创建容器时读走，密文变了要重建容器
  restartUnits = [ "docker-openlist.service" ];
};

virtualisation.oci-containers.containers.openlist = {
  environmentFiles = [ config.sops.templates."openlist.env".path ];
};
```

`sops.templates` 的内容先以占位符写进 `Nix store`，激活时由主机解密替换，链路上没有明文：

1. 求值：`sops.placeholder.<名字>` 是 `<SOPS:<名字的 sha256>:PLACEHOLDER>`，模板文本连着占位符一起进 `Nix store`
2. 激活：`sops-install-secrets` 读 `manifest.json`，解密密文，把模板里的占位符替换成真值，写到 `/run/secrets/rendered/<模板名>`，权限 0400、属主 root；渲染结果字节变了才按 `restartUnits` 重启对应单元
3. 取用：`environmentFiles` 被翻译成 `docker run --env-file /run/secrets/rendered/<模板名>`，docker 在宿主机上以 root 读这个文件，解析成容器进程的环境变量

值只在渲染时出现，所以 `environment = { X = config.sops.placeholder.<名字>; }` 会把占位符字面量塞进容器，机密只能走 `environmentFiles` 或挂渲染出来的文件

新字段加在 `secrets` 仓库的 `sops/secrets/hosts/<主机名>.yaml`，用 sops 编辑，字段名按用途分组，例如 `openlist/admin-password`、`kopia/password`。迁移旧服务时先沿用原值，不要顺手轮换

私有仓库推送后，在本仓库 `nix flake update secrets`（或 `just upp secrets`）并提交 `flake.lock`，否则部署用的还是锁定的旧密文

## 网络与端口

- `apps/default.nix` 里的 `docker-network-homelab` 单元检查 `homelab` 网络，不存在才按原参数创建，已存在就不动，避免正在运行的容器被换网络
- 服务之间用容器名互解，kopia 连 openlist 的 WebDAV 走的就是 `http://openlist:80/dav/main`
- 对外端口默认只发布到 Tailscale 地址。`127.0.0.1` 会让 tailnet 侧的 Gatus、Prometheus 也访问不到，`0.0.0.0` 等于直接放公网
- 例外只有两类，都按旧 Compose 原样保留：公网入口（`caddy` 的 80/443、`mosdns` 的 5054 明文 DNS）发布到所有地址；只给宿主机自己用的（`dnsmasq` 的 53、`sub-converter` 的 25500）发布到 `127.0.0.1`
- `caddy` 的 2019 不是管理面：它只是只读门面，只放行 `GET /metrics` 与 `GET /reverse_proxy/upstreams`（Prometheus 与 Homepage caddy widget 用），其余路径 403；Caddy 管理面在容器内的 unix socket 上，容器外与 tailnet 都够不到
- 需要宿主机网络栈的容器（`derp`、`hysteria2`、`anytls`、`crowdsec-firewall-bouncer`）写 `extraOptions = [ "--network=host" ]`，这时不要写 `networks`，对应端口由 `hosts/vps/common.nix` 的防火墙放行
- Docker 守护进程要等 tailscaled，`hosts/vps/common.nix` 里已有 `docker.service` 的 `after`/`wants`
- 新服务接入：`networks = [ "homelab" ];`，端口写 `"${address}:<宿主端口>:<容器端口>"`

## 生命周期与依赖

| 事项       | 行为                                                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 容器名     | 等于属性名，例如 `openlist`                                                                                                                                                    |
| unit 名    | `docker-<属性名>.service`                                                                                                                                                      |
| 启动前     | 模块先 `docker rm -f <容器名>`，从 compose 接管同名容器不用手工停旧容器                                                                                                        |
| 日志       | 默认 `journald`，`journalctl -u docker-<名字>`                                                                                                                                 |
| 重启       | `Restart=always`，间隔 10 秒，崩溃时不会把日志打满                                                                                                                             |
| 服务间依赖 | `dependsOn = [ "openlist" ]` 给退出联动与启动顺序                                                                                                                              |
| 等健康就绪 | 不要在 `ExecStartPre` 里轮询：它阻塞 unit 的启动任务，整次 `switch` 会被拖过 deploy-rs 的确认窗口而误回滚。让应用自己失败重试（`Restart=always`），见 `apps/kopia/default.nix` |

## 加一个服务的步骤

- [ ] 对照「从 Compose 抄字段」把声明写进 `apps/<服务名>.nix`
- [ ] 定端口与地址，写 `"${address}:<宿主端口>:<容器端口>"`
- [ ] 非机密参数进 `environment`，机密进 sops：加字段、加模板、挂 `environmentFiles`
- [ ] 私有仓库推送后 `just upp secrets` 刷新 `flake.lock`，否则部署读的是旧密文
- [ ] 附带文件放进服务目录，用 `${./文件名}` 挂载
- [ ] 需要等依赖就绪时，让服务自己失败重试，不要在 `ExecStartPre` 里等待
- [ ] 核对数据目录与命名卷的实际名字
- [ ] 新目录时，在主机 `default.nix` 的 `imports` 加一次
- [ ] 求值：`nix eval .#nixosConfigurations.<主机>.config.system.build.toplevel.drvPath`
- [ ] 部署：`just deploy vps-cc`
- [ ] 验收：`systemctl status docker-<名字>`、`journalctl -u docker-<名字>`、`docker ps`，再从 tailnet 侧试一次端口
- [ ] 回退：**顺序不能反**，否则容器会被前后两次清掉
  - 取回 home-ops 迁移前的 `compose/vps/`、`.env.tpl` 与被删的 task/ansible，备好凭据
  - 本仓库去掉该服务（或整套）声明并 `just deploy vps-cc`：nix 单元的停止与清理会 `docker rm -f` 同名容器，这一步结束时容器是停的
  - 在 home-ops 跑 `task compose:deploy:vps` 把 Compose 容器起回来（反序做的话，nix 单元的清理会把刚起的同名容器删掉）

## 当前已纳管的服务

`hosts/vps/vps-cc/apps/` 一个文件一个服务

| 服务                        | 形态                                          | 备注                                            |
| --------------------------- | --------------------------------------------- | ----------------------------------------------- |
| `node-exporter`             | 无状态：只读挂宿主机目录                      | 端口只到 Tailscale                              |
| `openlist`                  | 有状态：数据目录 + HTTP 健康检查              | 专门给 kopia 使用，连接 139 网盘                |
| `kopia`                     | 依赖型：openlist 可用后才真正跑起来           | 仓库配置由 sops 渲染，策略与入口脚本随目录挂    |
| `dnsmasq`                   | 容器：宿主解析入口                            | 配置含 sops 值，只发布 127.0.0.1:53             |
| `caddy`                     | 容器：公网入口 80/443                         | 镜像自带 Cloudflare DNS 与 CrowdSec AppSec 插件 |
| `crowdsec-agent`            | 容器：agent-only，连远程 LAPI                 | Caddy 的 AppSec 后端（`crowdsec-agent:7422`）   |
| `crowdsec-firewall-bouncer` | 容器 + host 网络：操作宿主机 iptables         | 与 NixOS 防火墙并行工作                         |
| `dhp`                       | 容器：Docker Hub 的 pull-through 代理         | 数据目录 `/data/docker/dhp/data`                |
| `dockerproxy`               | 容器：docker socket 只读代理                  | 给 tailnet 侧的 Gatus 与 Homepage 用            |
| `fluent-bit`                | 容器：读 docker socket 与 `/var/log`          | 日志转集群 VictoriaLogs，db 落在宿主机          |
| `mosdns`                    | 容器：配置烘在自建镜像里                      | 5054 仍对外（`vdns` 的明文 DNS 入口）           |
| `sub-converter`             | 容器：自建镜像                                | Caddy 按容器名反代，端口只发布到宿主 loopback   |
| `sbtools-server`            | 容器：自建镜像，单个私钥变量                  | 不发布端口，只有 Caddy 走 homelab 网络访问      |
| `derp`                      | 容器 + host 网络：TLS 由 Caddy 终止           | `8666/tcp`、`3478/udp`                          |
| `hysteria2`                 | 容器 + host 网络：复用 Caddy 的 wildcard 证书 | `10357/udp`                                     |
| `anytls`                    | 容器 + host 网络：入口脚本负责自签证书        | `5444/tcp`                                      |

只有 dnsmasq 试过走原生 module 但落不下来（`services.dnsmasq.configFile` 是 readOnly，配置只能由 `settings` 生成，而它含 sops 值）；其余服务各自的阻碍写在对应服务文件的头部注释里。判断标准是「原生 module 能否原样覆盖配置与进程语义」，不是「有没有 module」：`services.tailscale.derper`、`services.sing-box`、`services.fluent-bit` 都存在，但分别把 nginx、证书目录、单位硬化写死在 module 里，搬过去要改的就不只是声明了

旧声明（home-ops 的 `compose/vps/`）已随这次迁移整体删除，回退步骤见「加一个服务的步骤」最后一条（先撤本仓库声明，再起 Compose，顺序反了容器会被删两次）

## 相关

- 旧声明：home-ops 的 `compose/vps/docker-compose.yml`（已删除，历史里可查）
- 官方实现：nixpkgs 的 `nixos/modules/virtualisation/oci-containers.nix`
- 系统侧：`hosts/vps/common.nix`（tailscale、docker）、`05-vps.md`（接管与部署）
