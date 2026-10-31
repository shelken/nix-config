# server 角色、core 基线与系统密钥

日期: 2026-10-31

仓库长期只在 darwin 上用，NixOS 侧的 `core` 被塞进了笔记本与开发机才需要的东西（电源管理、mDNS 发布、监听 `0.0.0.0` 的 node_exporter、默认关闭的防火墙、X11 转发、无条件加入的 networkmanager 与 docker 组），无法作为公网 VPS 的起点，词汇表却把 `core` 定义为“常驻服务器”。现在 `core` 只是所有角色共有的基线（能登录、能用 nix、安全默认），多余的搬到 `gui`（电源管理）和 `tui`（avahi、node_exporter、诊断工具），NixOS 新增主角色 `server`：`core` 之上只加服务器职责，与 `tui` 并列，不含开发工具链。国内 NTP、docker 镜像源这类区域默认值留在 `core` 与可选功能里，位于国外的主机在自己的配置里覆盖，不为它们另立角色。

服务器的口令哈希走系统层 sops（可选功能 `nixos.sops`），与 `shelken.secrets.enable` 的用户态凭据无关：每台主机用自己单独生成的 age 密钥，只能解密给自己的那一个文件，不能解密 `default.yaml`；私钥在安装时用 `--extra-files` 放到固定路径，不从 SSH 主机密钥派生。服务商分配的网络参数不是密钥，且求值期就要用，sops 在激活期才解密、赶不上，所以放在私有 `secrets` 仓库里作为明文，经 flake 输入读取。

## 考虑过的替代方案

- **不新增角色，直接用 `core`**：`core` 要继续被所有主机包含，把笔记本与开发机的东西留在里面，公网服务器就要靠一连串 `mkForce` 去关闭，每台服务器都重复一遍
- **`server` 导入 `tui` 再去掉开发工具**：`tui` 的闭包约 7.8 GiB，包含 rust、ansible 等；Nix 模块无法只去掉“某个包”，只能反过来让开发机在 `core` 上加东西
- **服务器口令哈希放进 `vars/` 明文**：公开仓库里任何人可离线爆破，哈希强度不能完全替代保密
- **age 密钥由 SSH 主机密钥派生（sops-nix 默认）**：主机密钥泄露或轮换会同时影响密文，违背“登录归 SSH、解密归 age”
- **把 vps 的 age 公钥加进现有的 `default.yaml` 规则**：公网服务器被入侵就能解密你全部凭据

## 后果

- 之前依赖 `core` 自带 avahi、node_exporter、诊断工具、关闭防火墙的主机要自行导入，或改用 `tui`
- `docs/user-guide/02-features.md` 与 `GLOSSARY.md` 的角色表要带上 `server`；`AGENTS.md` 里的角色链描述也要更新
- 新增 `hosts/vps/` 目录会让 `calcUniformSchedule` 的备份时段整体平移一次
- 每台使用系统 sops 的服务器都要在 `secrets` 仓库里单独建一个 age 密钥和一个密文文件
- 机器第一次开机就要读的状态（age 私钥、tailscale 节点身份、SSH 主机密钥）只能在安装时用 `--extra-files` 放进新系统，不能事后补；这份清单没有声明在配置里，见 `hosts/vps/vps-cc/README.md`
- age 私钥可以替换：每台主机的密文同时写给了管理员公钥，丢了就换一把、`sops updatekeys`、刷新 `secrets` 输入，不需要另存备份
