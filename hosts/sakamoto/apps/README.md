# sakamoto：Compose 服务的声明与启动

`sakamoto` 的业务容器原先由 home-ops 的 `compose/sakamoto/` 声明并部署，现在声明在本目录。
运行时仍是 OrbStack + Compose：macOS 侧没有 `oci-containers` 这类原生模块，容器、命名卷与 `homelab` 网络都在 OrbStack 里。声明进 Nix store、含机密的配置由 sops 模板渲染、启动交给 launchd agent。

## 组成

| 文件                 | 作用                                                            |
| -------------------- | --------------------------------------------------------------- |
| `stack/compose.yaml` | 服务声明                                                        |
| `stack/configs/`     | Caddyfile、镜像 registry 配置、kopia 的策略与入口脚本：不含机密 |
| `default.nix`        | sops 密钥与两个模板、launchd agent、`sakamoto-compose` 命令行   |

`stack/` 整目录进 Nix store，里面只放容器要读到的文件：改 `default.nix` 或本文件不会换 store 路径，也就不会白白重建挂 `configs` 的容器

入口脚本 `stack/configs/kopia/entrypoint.sh` 在 git 里是 100755，进 store 后保留执行位，容器可以直接执行

渲染出来的两个文件都在 `~/.config/sops-nix/secrets/rendered/`，权限 0400，明文不进 Nix store：

| 渲染产物                                | 内容                                     | 谁用                                        |
| --------------------------------------- | ---------------------------------------- | ------------------------------------------- |
| `sakamoto-compose.env`                  | 域名、数据目录、外接盘路径、口令与 token | `--env-file`，compose 里所有 `${...}` 插值  |
| `sakamoto-kopia-main-repository.config` | 云端仓库的 WebDAV 地址与凭据             | `configs.kopia_main_repository_config.file` |

## 启动与收敛

launchd agent（Label `space.ooooo.sakamoto-compose`，`gui` 域）负责拉起与对账：

| 改了什么            | 收敛                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------- |
| `stack/` 下任何文件 | store 路径变，`sakamoto-compose` 与 plist 跟着变，agent 重载后立刻 `up`，只重建受影响的服务 |
| 只有密钥的值        | plist 不变，`WatchPaths` 盯住渲染目录，sops 写完 env 立刻 `up`                              |
| 都没有变化          | `StartInterval` 15 分钟兜底                                                                 |

`up` 先等 OrbStack 与渲染出的 env，再逐个检查数据目录：外接盘没挂载时直接失败，不让 Docker 以 root 新建空目录。日志在 `~/Library/Logs/sakamoto-compose.log`

## 切换

前置：私有 `secrets` 仓库里补上 `default.nix` 中 `secretNames` 列出的键，推送后在本仓库 `just upp secrets` 刷新 lock

1. 构建：在 sakamoto 上 `just hm-build`；从别的机器只做轻量求值 `nix eval .#darwinConfigurations.sakamoto.config.home-manager.users.shelken.home.activationPackage.drvPath`
2. 确认 `~/.config/sops/age/keys.txt` 能解开密文，然后 `just hm`
3. 看 agent 是否接管：`launchctl list | grep sakamoto-compose`、`tail -f ~/Library/Logs/sakamoto-compose.log`

这一步会把 `configs` 的挂载源从 `~/homelab-compose` 换成 Nix store 路径，容器重建一次；命名卷（`homelab-compose_kopia_cache`、`homelab-compose_kopia_local_cache`）不动，kopia 的对账指纹与缓存保留

## 回退

1. 撤掉 `hosts/sakamoto/home.nix` 里的 `imports = [ ./apps ]` 并 `just hm`：agent 与命令行消失，容器继续跑但不再受管理
2. 旧目录 `~/homelab-compose` 与旧入口（home-ops 的 `task compose:deploy:sakamoto`）在删除前都能回退：两边的声明指向同一批容器，回退只是把 `configs` 的挂载源换回去

## 日常操作

```bash
sakamoto-compose up         # agent 每 15 分钟跑的就是它
sakamoto-compose recreate   # 改了 configs/ 里挂载的文件内容后
sakamoto-compose status
sakamoto-compose logs
sakamoto-compose check      # 只校验解析与插值，不动容器
```

镜像升级：`stack/compose.yaml` 里的 tag 由 renovate 的 `sakamoto container images` 规则合成一个 PR，手动合并后 `just hm` + `sakamoto-compose up` 生效
