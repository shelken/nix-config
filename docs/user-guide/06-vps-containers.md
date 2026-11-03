# VPS 容器：手动交接两个试点

## 范围

先审核并合并试点 PR，再手动执行本流程。PR 本身不修改主机导入，不启动容器，不读取线上密钥，也不修改 home-ops。

| 应用             | 本次验证                            | 保持的调用方式                             |
| ---------------- | ----------------------------------- | ------------------------------------------ |
| `sbtools-server` | sops 私钥、运行时标签、无宿主机端口 | Caddy 继续通过原容器名称和内部端口访问     |
| `sub-converter`  | sops 环境文件、本机端口、安全限制   | Caddy 继续通过原容器名称访问；保留本机端口 |

两个应用都没有持久化业务卷。OpenList/Kopia、HTTP 健康等待、业务数据卷和 Ansible 清理均留在后续批次。

本流程按以下顺序执行：准备密钥 → 只启用网络检查 → 一次交接一个应用 → 实际验证 → 最后验收。

## 1. 准备工作区和恢复材料

在 Mac 的 nix-config 工作区中执行。将变量替换为你自己的信息；不要把真实值提交到公开仓库。

```bash
HOST='<主机配置名>'
TARGET='<已有 SSH 别名>'
SECRETS_REPO='<私有密钥仓库工作区>'
SOPS_FILE="$SECRETS_REPO/sops/secrets/hosts/$HOST.yaml"
HOST_FILE="hosts/vps/$HOST/default.nix"

umask 077
OCI_PILOT_DIR=$(mktemp -d)
```

- 保持一个独立 SSH 会话，用于查看状态和执行应用回退。
- 确认工作区包含已审核的代码；记录当前提交与当前系统 generation。
- 备份当前 Compose 声明、已渲染环境文件及部署命令。恢复材料放在受限目录，不加入 Git。
- 暂停 `task compose:deploy:vps`、整组 `docker compose up` 和旧组的重建操作。旧声明仍包含试点应用，运行这些命令可能重新创建它们。
- 迁移期间不要对旧组执行 `docker compose down`；共享网络仍被其他应用使用。

## 2. 从现有容器准备密钥值

以下命令只读远端 Docker 元数据，将结果写入本地受限临时目录。元数据含明文环境变量，不要打印、上传或提交这些文件。

```bash
ssh "$TARGET" sudo docker network inspect homelab \
  | jq -e '.[0] | {Name, Driver, EnableIPv6, Internal, Attachable, Options, IPAM}' \
  > "$OCI_PILOT_DIR/network.snapshot.json"
ssh "$TARGET" sudo docker inspect sbtools-server \
  > "$OCI_PILOT_DIR/sbtools.inspect.json"
ssh "$TARGET" sudo docker inspect sub-converter \
  > "$OCI_PILOT_DIR/subconverter.inspect.json"

jq -Rs . "$OCI_PILOT_DIR/network.snapshot.json" > "$OCI_PILOT_DIR/network.json"
jq -e '
  .[0].Config.Env
  | map(select(startswith("SERVER_PRIVATE_KEY=")) | ltrimstr("SERVER_PRIVATE_KEY="))
  | if length == 1 and .[0] != "" then .[0] else error("检查现有私钥变量") end
' "$OCI_PILOT_DIR/sbtools.inspect.json" > "$OCI_PILOT_DIR/sbtools-private-key.json"
jq -e '
  .[0].Config.Env
  | map(select(startswith("API_TOKEN=")) | ltrimstr("API_TOKEN="))
  | if length == 1 and .[0] != "" then .[0] else error("检查现有 API token") end
' "$OCI_PILOT_DIR/subconverter.inspect.json" > "$OCI_PILOT_DIR/subconverter-api-token.json"
jq -e '
  .[0].Config.Env
  | map(select(startswith("MANAGED_PREFIX=https://sub."))
        | ltrimstr("MANAGED_PREFIX=https://sub.") | rtrimstr("/"))
  | if length == 1 and .[0] != "" then .[0] else error("检查现有域名配置") end
' "$OCI_PILOT_DIR/subconverter.inspect.json" > "$OCI_PILOT_DIR/main-domain.json"
```

每个命令都必须成功，再继续。四个输出值均为 JSON 编码的字符串。域名、私钥和 token 必须为单行；如果原值包含换行，停止交接，先调整交付方式，不能擅自修改原值。

把它们写入现有主机密文。`sops set` 使用该文件已有的加密接收方，不新建解密私钥。

```bash
for field in network main-domain sbtools-private-key subconverter-api-token; do
  sops set --value-file "$SOPS_FILE" \
    "[\"vps-containers\"][\"$field\"]" "$OCI_PILOT_DIR/$field.json"
done
```

在私有密钥仓库检查并提交密文，推送到现有 secrets input 跟踪的分支。回到 nix-config 更新这一个 input：

```bash
nix flake update secrets
```

确认主机已有的解密私钥仍能读取更新后的密文。不要将临时明文加入 Git 或 Nix store；不要同时轮换凭据。

## 3. 先启用网络检查，不交接应用

在主机文件中保留原有配置，增加 `self` 参数，在已有 `imports` 中追加一个模块：

```nix
self.modules.nixos.vps-container-network
```

沿用现有 VPS 的 Mac 部署方式，见 [VPS 指南](05-vps.md#日常更新)。先运行：

```bash
git add "$HOST_FILE" flake.lock
just plan "$HOST" deploy
just deploy "$HOST" --dry-activate
```

检查计划中没有应用 unit 和网络、防火墙等无关变化，再执行：

```bash
just deploy "$HOST"
ssh "$TARGET" sudo systemctl start vps-container-network.service
ssh "$TARGET" sudo systemctl status vps-container-network.service --no-pager
```

本步骤会安装网络密文，启动网络核对。现有参数一致则复用；不存在则按记录创建。参数冲突时失败，保持现有网络，不自动重建。失败时停止流程，先处理差异。

## 4. 每次只交接一个应用

第一批使用 `APP=sbtools-server`，第二批使用 `APP=sub-converter`。前一批验证通过后再执行后一批。

```bash
APP=sbtools-server
```

在主机 `imports` 中追加该应用对应的模块，保留网络模块：

| APP              | 追加的 import                           |
| ---------------- | --------------------------------------- |
| `sbtools-server` | `self.modules.nixos.vps-sbtools-server` |
| `sub-converter`  | `self.modules.nixos.vps-sub-converter`  |

### 4.1 停机前检查

1. 保存修改后运行 `git add "$HOST_FILE"`。
2. 执行 `just plan "$HOST" deploy` 和 `just deploy "$HOST" --dry-activate`，核对变更只涉及预期应用。
3. 从 Nix 声明读取固定镜像引用，在目标机预拉取，再比较它与现有运行镜像的本地 ID：

```bash
IMAGE=$(nix eval --raw ".#nixosConfigurations.$HOST.config.virtualisation.oci-containers.containers.$APP.image")
ssh "$TARGET" sudo docker pull "$IMAGE"
OLD_IMAGE=$(ssh "$TARGET" sudo docker inspect --format '{{.Image}}' "$APP")
NEW_IMAGE=$(ssh "$TARGET" sudo docker image inspect --format '{{.Id}}' "$IMAGE")
test "$OLD_IMAGE" = "$NEW_IMAGE"
```

比较失败时停止。先把声明改为当前运行镜像对应的不可变引用，再审核；本次不顺带升级应用。

4. 核对旧容器的命令、环境变量、端口、安全限制和 Homepage 标签。确认只有预期容器占用名称、本机端口，且网络检查仍通过。
5. 记录切换前的实际客户端操作结果，作为切换后的对照。准备好完整恢复材料后，才开始停机。

原容器重命名前只执行计划和 dry activation。所有权检查会在 OCI 清理前拒绝替换未带 Nix 管理标记的同名容器；若看到此错误，先停止新 unit，再按交接步骤处理。

### 4.2 交接名称和管理权

以下命令会更改旧容器的重启策略、停止它，并重命名保留。先确认 `APP` 为本批应用，备份名称尚未被使用。该步骤由你手动执行，不删除旧容器。

```bash
ssh "$TARGET" sudo docker update --restart=no "$APP"
ssh "$TARGET" sudo docker stop "$APP"
ssh "$TARGET" sudo docker rename "$APP" "compose-backup-$APP"
```

随后在 Mac 激活已经审核的主机配置：

```bash
just deploy "$HOST"
```

新 unit 负责创建同名容器。旧容器保留原镜像和环境，但停止并关闭自动重启。不要重新运行旧 Compose 部署。

### 4.3 验证后再进入下一批

```bash
ssh "$TARGET" sudo systemctl status "docker-$APP.service" --no-pager
ssh "$TARGET" sudo journalctl -u "docker-$APP.service" -n 60 --no-pager
```

必须完成以下实际验证：

- 确认 Caddy 仍能按原容器名称和内部端口访问该应用，查看代理错误日志。
- `sbtools-server`：使用现有客户端完成一次实际订阅信息同步，与切换前结果比较。
- `sub-converter`：访问现有 `/version` 入口，再用一份已有订阅完成转换；确认本机端口仍只绑定环回地址。
- 确认 Homepage 标签仍被 Docker 发现，页面入口保持原地址。
- 确认其他 Compose 应用未重启，备份容器保持停止且 restart policy 为 `no`。

`running` 和 SSH 可用都不能代替应用验证。deploy-rs 的系统回退不会自动恢复旧容器管理权。

任一检查失败就停止后续批次，执行下一节的应用回退。不要用后续迁移掩盖失败。

## 5. 单个应用回退

先在目标机停止新 unit：

```bash
ssh "$TARGET" sudo systemctl stop "docker-$APP.service"
```

停止 OCI unit 会清理它创建的新容器。这两个试点没有数据卷，旧备份容器不在清理目标中。不要手动删除旧备份容器或共享网络。

在主机文件中仅移除该应用新增的 import，保留网络和其他已通过验收的应用 import。重新运行 `git add "$HOST_FILE"`，再执行 `just deploy "$HOST"`。

确认新 unit 已退出管理，原容器名称空闲后，恢复旧实例：

```bash
ssh "$TARGET" sudo docker rename "compose-backup-$APP" "$APP"
ssh "$TARGET" sudo docker update --restart=always "$APP"
ssh "$TARGET" sudo docker start "$APP"
```

再次执行实际客户端验证。恢复后仍暂停旧整组部署，直到核对清楚其他已迁移应用的归属。已经通过验收的另一试点不能被旧 Compose 重新接管。

## 6. 收尾和后续批次

- 将已验证的主机 imports 和 secrets lock 更新单独提交，记录每个应用的管理者。
- 旧 Compose 声明仍含试点；迁移期间禁止运行整组旧部署。后续 home-ops 变更移除试点声明后，才能恢复旧任务对其余应用的部署。
- 旧备份容器、网络、卷和 BWS 条目均不在本次自动清理范围。实际删除前单独确认。
- 结束或中止本流程都要清理本地临时明文：`rm -r -- "$OCI_PILOT_DIR"`。
- 后续批次再实现 OpenList/Kopia 的启动健康等待、数据卷交接与其他应用；最后清理 VPS 专用 Ansible 和旧部署入口。

后续变更由 Renovate 提出固定镜像更新 PR；人工审核、合并、部署。sops 模板内容变化仅重启使用该模板的应用；共享域名变化会影响两个应用的标签，两个 unit 都需要更新。
