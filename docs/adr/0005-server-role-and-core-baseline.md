# server 角色、core 基线与系统密钥

日期 2026-10-31

NixOS 的 `core` 曾包含笔记本与开发机配置，无法作为公网 VPS 的起点。现在 `core` 收敛为全部主角色共有的最小基线，NixOS 新增与 `tui` 并列的 `server` 主角色，服务器口令哈希改走系统层 sops 并与用户态凭据隔离

## 规则

- `core` MUST 只放全部主角色下所有主机都需要的基线，只要有一台主机不需要就 MUST 移到对应角色或可选功能
- `server` 为 NixOS 专用主角色，只包含 `core` 与常驻服务器职责，MUST NOT 包含开发工具链
- 区域默认值 MAY 留在 `core` 或可选功能，国外主机 SHOULD 在自身配置覆盖，MUST NOT 为区域另立角色
- 服务器口令哈希 MUST 走系统层 `nixos.sops` 可选模块，与用户态 `shelken.secrets.enable` 隔离。每台服务器 MUST 使用独立生成的 age 密钥，其公钥 MUST NOT 加入 `default.yaml` 的 recipient，私钥 MUST NOT 从 SSH 主机密钥派生
- 开机即需状态（age 私钥、tailscale 节点身份、SSH 主机密钥）MUST 在装机时写入新系统，具体步骤见 `hosts/vps/vps-cc/README.md`

## 考虑过的替代方案

- 公网服务器直接用 `core` 并写一串 `mkForce` 关掉桌面和开发配置。每台服务器都要重复覆盖，容易遗漏
- `server` 导入 `tui` 再删开发工具。Nix 模块无法从已合并列表里移除某个包
- 服务器口令哈希明文放在公开仓库 `vars/`。任何人都可离线爆破
- 由 SSH 主机密钥派生 age 密钥。主机密钥泄露或轮换会同时破坏密文边界
- 把服务器 age 公钥加入 `default.yaml`。单台公网服务器被攻破就会泄露全部个人凭据
