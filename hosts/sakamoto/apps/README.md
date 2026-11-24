# sakamoto：Compose 服务的声明与启动

`sakamoto` 的业务容器基于 OrbStack + Compose，声明在同目录 `compose.yaml`、`configs/` 与 `default.nix`；机密由 sops 渲染为 env，由 launchd agent `space.ooooo.sakamoto-compose` 在登录、外接盘挂载与每 15 分钟收敛启动

## 跨文件与运维约束

- `configs/caddy/Caddyfile` 中 `internal-access` 站点须与路由器 `hosts/router-mine/home-ops/dns.nix` 的自举名一一对应
- 配置文件必须经独立 store 路径写入 env 后用 `volumes:` 挂载（`configs:` 不计入 Compose 服务 hash，修改不会触发重建）；含机密文件不直接挂盘，改由环境变量交由入口脚本生成，避免 sops 换代后符号链接导致容器读失败
- `configs/kopia/local/` 将本地仓库内容与元数据缓存压到 500M（硬上限 1G）：本地仓库就在外接盘上，更大缓存只是重复占用内置盘
- `compose.yaml` 由 `~/.config/sakamoto-compose/compose.yaml` 固定路径引用，避免 store 路径变动导致 OrbStack 拆分服务分组；外接盘未挂载时 `up` 提前中止，不启动 OrbStack 也不让 Docker 建空目录

## 验证与日常操作

- 验证改动：本机执行 `just hm-build`，异机求值 `nix eval .#darwinConfigurations.sakamoto.config.home-manager.users.shelken.home.activationPackage.drvPath`；新增机密先更新 `secrets` 仓库再 `just upp secrets`
- 排查状态：`launchctl list | grep sakamoto-compose` 与 `tail -f ~/Library/Logs/sakamoto-compose.log`；完整子命令见 `sakamoto-compose --help`
- 镜像升级：`compose.yaml` tag 由 Renovate `homelab container images` 规则（与 `vps-cc` 合并 PR）更新，合并后 `just hm`（或 `just deploy sakamoto`）并运行 `sakamoto-compose up`（或等待 15 分钟自动收敛）
