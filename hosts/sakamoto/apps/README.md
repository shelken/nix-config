# sakamoto：Compose 服务的声明与启动

`sakamoto` 的业务容器原先由 home-ops 的 `compose/sakamoto/` 声明并部署，现在声明在本目录。
运行时仍是 OrbStack + Compose：macOS 侧没有 `oci-containers` 这类原生模块，容器、命名卷与 `homelab` 网络都在 OrbStack 里。声明进 Nix store、口令由 sops 模板渲染、启动交给 launchd agent。

## 组成

| 文件           | 作用                                                                                    |
| -------------- | --------------------------------------------------------------------------------------- |
| `compose.yaml` | 服务声明                                                                                |
| `configs/`     | Caddyfile、镜像 registry 配置、kopia 的策略与入口脚本：不含机密                         |
| `default.nix`  | sops 密钥与 env 模板、launchd agent、`sakamoto-compose` 命令行、各配置文件的 store 路径 |

渲染出来的 `~/.config/sops-nix/secrets/rendered/sakamoto-compose.env`（权限 0400，明文不进 Nix store）是 compose 的唯一 `--env-file`：

- 域名、数据目录、口令与 token（来自 sops），外接盘的两个固定路径（明文，`default.nix` 的 `externalDisks`）
- `CADDYFILE`、`MIRROR_CONFIG` 等变量：`configs/` 里每个文件各自的 store 路径，`compose.yaml` 用 `volumes:` 把它们挂进容器

入口脚本 `modules/features/backup/_kopia-server/entrypoint.sh` 在 git 里是 100755，进 store 后保留执行位，容器可以直接执行。

## 配置怎么触发重建

Compose 的服务 hash 不包含 `configs:` 的文件路径与内容，所以配置文件**不能**用 `configs:` 挂：改了文件，`up` 也不会重建容器。`volumes:` 的源路径在 hash 里，所以这里的约定是：

- 每个配置文件单独进 store，路径随内容变
- 路径写进 env 文件，`compose.yaml` 用 `volumes: - ${CADDYFILE}:...:ro` 引用
- 改哪个文件，只重建用到它的服务（改 `mirror-config.yaml` 重建四个 mirror，改共用的 `entrypoint.sh` 重建两个 kopia）

kopia 的 `entrypoint.sh` 与云端仓库的 `policy.json` 和 vps-cc 共用同一份（`modules/features/backup/_kopia-server/`），改动两台主机一起生效；`configs/kopia/local/` 是只有 sakamoto 用的本地仓库配置。

含机密的内容不挂文件：kopia 云端仓库的 WebDAV 地址与凭据以环境变量交给容器，`entrypoint.sh` 启动时生成 `repository.config`。原因是 sops 渲染文件在符号链接下面，密钥轮换换代后，运行中的容器挂着旧目录，读文件会得到 `Operation not permitted`。

## 启动与收敛

launchd agent（Label `space.ooooo.sakamoto-compose`，`gui` 域）负责拉起与对账：

| 改了什么                                      | 收敛                                                                                                              |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `compose.yaml`、`configs/` 里的文件、密钥的值 | plist 不变，下一轮 `StartInterval`（≤15 分钟）的 `up` 重建受影响的容器；`default.nix` 里 CLI 本身变了才会立刻重载 |
| 都没有变化                                    | `StartInterval` 15 分钟兜底                                                                                       |

改了 `compose.yaml`、配置或密钥想立刻生效：`sakamoto-compose up`。

`docker compose -f` 用的是固定路径 `~/.config/sakamoto-compose/compose.yaml`（符号链接，指向 store）。Compose 创建容器时把这个路径写进 `config_files` 与 `working_dir` 标签，OrbStack 按它分组；用 store 路径的话，每改一次 `compose.yaml` 路径就变，没被重建的容器保留旧标签，会多出一组。

没有用 `WatchPaths` 监视渲染目录：它在符号链接下面，sops 换代后 launchd 的监视时灵时不灵（实测三轮换代只触发一轮）。

`up` 先等 OrbStack 与渲染出的 env，再逐个检查数据目录：外接盘没挂载时直接失败，不让 Docker 以 root 新建空目录。日志在 `~/Library/Logs/sakamoto-compose.log`。

## 切换

前置：私有 `secrets` 仓库里补上 `default.nix` 中 `secretNames` 列出的键，推送后在本仓库 `just upp secrets` 刷新 lock。

1. 构建：在 sakamoto 上 `just hm-build`；从别的机器只做轻量求值 `nix eval .#darwinConfigurations.sakamoto.config.home-manager.users.shelken.home.activationPackage.drvPath`
2. 确认 `~/.config/sops/age/keys.txt` 能解开密文，然后 `just hm`
3. 看 agent 是否接管：`launchctl list | grep sakamoto-compose`、`tail -f ~/Library/Logs/sakamoto-compose.log`
4. 第一轮 `up` 会重建 7 个容器：caddy、四个 mirror、两个 kopia（配置文件从 `configs:` 改成了 `volumes:`，服务定义变了）；rustfs、dockerproxy、nvidia-dls 不动。命名卷（`homelab-compose_kopia_cache`、`homelab-compose_kopia_local_cache`）不动，kopia 的对账指纹与缓存保留
5. 验收通过后，手动删除旧目录 `~/homelab-compose`：里面有旧流程渲染出的明文 `.env` 与 `repository.config`

## 回退

1. 撤掉 `hosts/sakamoto/home.nix` 里的 `imports = [ ./apps ]` 并 `just hm`：agent 与命令行消失，容器继续跑但不再受管理
2. 旧目录 `~/homelab-compose` 与旧入口（home-ops 的 `task compose:deploy:sakamoto`）在删除前都能回退：旧入口 `-- --force-recreate` 部署一次，配置文件的挂载源就换回旧目录

## 日常操作

```bash
sakamoto-compose up         # agent 每 15 分钟跑的就是它
sakamoto-compose recreate   # 无条件重建全部容器，排障用
sakamoto-compose status
sakamoto-compose logs
sakamoto-compose check      # 只校验解析与插值，不动容器
```

镜像升级：`compose.yaml` 里的 tag 由 renovate 的 `sakamoto container images` 规则合成一个 PR，合并后 `just hm`（或 `just deploy sakamoto`），再 `sakamoto-compose up`（或等 15 分钟的 agent），只重建 tag 变了的容器。
