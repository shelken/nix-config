# sakamoto：Compose 服务的声明与切换

`sakamoto` 的业务容器原先由 home-ops 的 `compose/sakamoto/` 声明并部署，现在声明在本目录。
运行时仍是 OrbStack + Compose：macOS 侧没有 `oci-containers` 这类原生模块，容器、命名卷与 `homelab` 网络都在 OrbStack 里。变的是三件事：声明进 Nix store、含机密的配置由 sops 模板渲染、启动交给 launchd agent。

## 组成

| 文件           | 作用                                                                                                                             |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `compose.yaml` | 服务声明。与旧 compose 的差异只有三处：顶部 `name: homelab-compose`、两个外接盘路径改成 env 插值、kopia 云端仓库配置指向渲染路径 |
| `configs/`     | Caddyfile、镜像 registry 配置、kopia 的策略与入口脚本：不含机密，随目录进 store                                                  |
| `default.nix`  | sops 密钥与两个模板、launchd agent、`sakamoto-compose` 命令行                                                                    |

渲染出来的两个文件都在 `~/.config/sops-nix/secrets/rendered/`，权限 0400，明文不进 Nix store：

| 渲染产物                                | 内容                                     | 谁用                                        |
| --------------------------------------- | ---------------------------------------- | ------------------------------------------- |
| `sakamoto-compose.env`                  | 域名、数据目录、外接盘路径、口令与 token | `--env-file`，compose 里所有 `${...}` 插值  |
| `sakamoto-kopia-main-repository.config` | 云端仓库的 WebDAV 地址与凭据             | `configs.kopia_main_repository_config.file` |

## 切换

前置：私有 `secrets` 仓库里补上 `default.nix` 中 `secretNames` 列出的键，值沿用旧 Bitwarden 条目 `compose-sakamoto` 的字段，不要顺手轮换；推送后在本仓库 `just upp secrets` 刷新 lock。

1. 构建：在 sakamoto 上 `just hm-build`，从别的机器只做轻量求值 `nix eval .#darwinConfigurations.sakamoto.config.home-manager.users.shelken.home.activationPackage.drvPath`
2. 确认 `~/.config/sops/age/keys.txt` 能解开密文，然后 `just hm`
3. 看 agent 是否接管：`launchctl list | grep sakamoto-compose`、`tail -f ~/Library/Logs/sakamoto-compose.log`
4. 逐项核对下面的验收清单
5. 稳定几天后再删旧的 `~/homelab-compose`：它是回退路径

启动时容器会被重建一次：`configs` 的挂载源从 `~/homelab-compose` 换成了 Nix store 路径。命名卷（`homelab-compose_kopia_cache`、`homelab-compose_kopia_local_cache`）不动，kopia 的对账指纹与缓存都保留。

## 验收清单

- [ ] 10 个容器都在：`sakamoto-compose status`
- [ ] `docker volume ls` 里仍是 `homelab-compose_kopia_*`，没有多出新卷
- [ ] caddy：管理接口有响应，内网域名能反代到 rustfs 与四个镜像源
- [ ] 四个 registry mirror：`/v2/` 有响应
- [ ] rustfs：控制台与 S3 端口有响应，数据目录仍是旧的（没被新建空目录接过）
- [ ] nvidia-dls：许可证接口有响应
- [ ] kopia 与 kopia-local：`kopia snapshot list` 能看到旧快照，下一轮计划任务成功，`hostname` 仍是 `sakamoto` / `sakamoto-local`
- [ ] `cat ~/Library/LaunchAgents/space.ooooo.sakamoto-compose.plist`：含 `RunAtLoad`、`StartInterval = 900` 与 `WatchPaths`
- [ ] 外接盘未挂载时 `sakamoto-compose up` 直接失败并打印缺失目录（重启后盘未挂载时观察）
- [ ] 改一次 `configs/caddy/Caddyfile`，`just hm` 后 `sakamoto-compose up` 会重建 caddy 容器并生效

## 回退

1. 撤掉 `hosts/sakamoto/home.nix` 里的 `imports = [ ./apps ]` 并 `just hm`：agent 与命令行消失，容器继续跑但不再受管理
2. home-ops 侧的删除 PR 未合并时，直接 `task compose:deploy:sakamoto -- --force-recreate` 就回到旧行为（旧目录 `~/homelab-compose` 还在）
3. 两边的声明指向同一批容器，回退只是把 `configs` 的挂载源换回 `~/homelab-compose`

## 日常操作

```bash
sakamoto-compose up         # agent 每 15 分钟跑的就是它
sakamoto-compose recreate   # 改了 configs/ 里挂载的文件内容后
sakamoto-compose status
sakamoto-compose logs
sakamoto-compose check      # 只校验解析与插值，不动容器
```

镜像升级：`compose.yaml` 里的 tag 由 renovate 的 `sakamoto container images` 规则合成一个 PR，手动合并后 `just hm` + `sakamoto-compose up` 生效。

## 与旧 Compose 的差异

- `UID`、`GID` 与通用 `TZ`：旧 `.env` 里有，但没有任何服务引用，没有搬
- 外接盘路径：旧文件里写死，现在由 sops 渲染，公开仓库里不出现
- 旧的 `task compose:deploy:sakamoto` 先跑 `docker compose pull --policy missing`，新入口不拉镜像：`up -d` 在本地缺镜像时同样会拉，语义一致
- 入口脚本仍是 `entrypoint: ["/app/scripts/entrypoint.sh"]`：文件在 git 里是 100755，进 store 后保留执行位，容器可直接执行
