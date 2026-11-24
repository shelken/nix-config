# router-mine

## 引入原则

- 适用于 OpenWrt 及其衍生系统，更换路由器时可直接迁移
- 收录路由器核心职责必需的配置（防火墙、DHCP、DNS）、与 `home-ops` 联动配置以及明确需要的服务（如 watchcat）
- 同一服务的关联配置内聚在同一文件或同一目录

## 命名约定

- 规则与段的 `name` 只用 ASCII，不用中文：nuci diff 会按字节把非 ASCII 显示为乱码，导致 `just router::preview` 始终报出伪变更

## 热点救灾切换

`wireless.nix` 的 STA 热点接口（默认 `disabled = "1"`）与 `dhcp.nix` 的 `hotspot` 段（`ra/ndp = "relay"`）用于主链路不可用时手动切换为手机热点出口：

1. 在 LuCI 中停用 `wan` / `wan6`
2. 启用热点 STA Wi-Fi 接口连接上游热点
3. 将 IPv6 中继的 `master` 从 `wan` 切换为 `hotspot` / `hotspot_v6`

恢复主链路时反向操作；切回 `wan` 并停用 STA 接口后再执行 `just router::push`（`push` 会检测启用中的 STA 接口并阻止误关断网）。
