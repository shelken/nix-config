# VPS 容器试点

通过现有 `flake.modules.nixos` 导出三个可选模块。默认主机不导入它们，合并不会激活容器。

| 模块                    | 职责                                                         |
| ----------------------- | ------------------------------------------------------------ |
| `vps-container-network` | 从主机密文读取共享网络快照，核对或创建 `homelab`；不删除网络 |
| `vps-sbtools-server`    | 原容器命令、安全限制、私钥环境文件和 Homepage 标签           |
| `vps-sub-converter`     | 原环回端口、环境变量、安全限制和 Homepage 标签               |

主机已有的 sops 密文需增加 `vps-containers` 下的 `network`、`main-domain`、`sbtools-private-key`、`subconverter-api-token`。`network` 为 Docker inspect 提取后的 JSON 字符串。应用模块声明密钥和模板，主机负责选择密文文件及解密私钥。

应用依赖网络 unit。网络输入保留驱动、IPv6、内部/可附加标志、驱动选项和 IPAM，忽略网络 ID 与旧 Compose 标签。参数不一致即失败；移除模块和停止 unit 都不删除网络。

应用使用 Docker backend，保留容器名和原网络调用。sops 模板的 `restartUnits` 处理环境文件与标签变化；unit 使用 `Restart=always` 延续原重启意图。镜像固定 tag 和多架构索引 digest，由 Renovate 提 PR，人工部署。

启动前先检查同名容器的 `io.shelken.nix-managed` 标记。旧 Compose 容器没有该标记时，拒绝进入 OCI 的清理步骤；必须先完成手动停止和重命名。停止和失败后的清理也重新检查所有权，并按核对到的容器 ID 操作，避免默认 `postStop` 在启动失败后删除旧实例。新容器保留该标记，以便后续正常重建。

`system.build.vps-container-network` 暴露网络检查程序，接受 `--check NETWORK_JSON` 或 `--ensure NETWORK_JSON`。前者不创建网络，后者仅在缺失时创建；两者均不修改已有网络参数。

手动交接、应用验证和回退见 [用户流程](../../../docs/user-guide/06-vps-containers.md)。同一应用只能由一个管理者运行，旧 Compose 的整组部署必须在交接期间暂停。
