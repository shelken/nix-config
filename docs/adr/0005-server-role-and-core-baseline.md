# server 角色、core 基线与系统密钥

日期: 2026-10-31

仓库长期只在 darwin 上用，NixOS 侧 `core` 塞进了笔记本与开发机才需要的东西（电源管理、mDNS 发布、监听 `0.0.0.0` 的 node_exporter、默认关闭的防火墙、X11 转发、无条件加入的 networkmanager 与 docker 组），无法作为公网 VPS 的起点。现在 `core` 收敛为所有角色共有的基线，NixOS 新增主角色 `server`

## 规则

- `core` MUST 只放所有主角色下全部主机都需要的基线（能登录、能用 nix、安全默认），但凡一台主机不需要就 MUST 移到对应角色或可选功能
- `server` 为 NixOS 专用主角色：`core` 之上只加常驻服务器职责，与 `tui` 并列，MUST NOT 包含开发工具链
- 区域默认值（国内 NTP、docker 镜像源）MAY 留在 `core` 与可选功能；位于国外的主机 SHOULD 在自己的配置里覆盖，MUST NOT 为区域另立角色
- 服务器口令哈希走系统层 sops（可选功能 `nixos.sops`），与 `shelken.secrets.enable` 的用户态凭据无关：每台主机用单独生成的 age 密钥，只能解密给自己的那一个文件，其 age 公钥 MUST NOT 加入 `default.yaml` 的 recipient；私钥 MUST 在安装时用 `--extra-files` 放到固定路径，MUST NOT 从 SSH 主机密钥派生
- 开机即需状态（age 私钥、tailscale 节点身份、SSH 主机密钥）MUST 在安装时放入新系统，MUST NOT 事后补，清单见 `hosts/vps/vps-cc/README.md`
- 服务商分配的网络参数不是密钥且求值期就要用，sops 激活期才解密，MUST 放私有 `secrets` 仓库作明文，经 flake 输入读取

## 考虑过的替代方案

- 不新增角色直接用 `core`：公网服务器要靠一连串 `mkForce` 关闭笔记本配置，每台重复一遍
- `server` 导入 `tui` 再去开发工具：`tui` 闭包约 7.8 GiB，Nix 模块删不掉「某个包」
- 口令哈希放 `vars/` 明文：公开仓库可离线爆破
- age 由 SSH 主机密钥派生：主机密钥泄露或轮换同时影响密文
- age 公钥加进 `default.yaml`：公网服务器被入侵就能解密全部凭据

## 后果

- 原依赖 `core` 自带 avahi、node_exporter、诊断工具、关防火墙的主机 MUST 自行导入或改用 `tui`
- 在 `hosts/default.nix` 登记新服务器主机可能改变 `calcUniformSchedule` 中排序靠后主机的备份时段
- 每台用系统 sops 的服务器 MUST 在 `secrets` 仓库单独建 age 密钥与密文文件；密文同时写给管理员公钥，密钥丢失可换新并 `sops updatekeys`，无需另存备份
