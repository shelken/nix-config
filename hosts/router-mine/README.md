## 引入原则

- 适用范围: OpenWrt 及其衍生系统
- 配置是足够`路由器核心职责`且必须的(例如防火墙的配置/DHCP/DNS), 应该能在切换路由器(OpenWrt及其衍生系统)时能够丝滑引入
- 如果和home-ops有关的, 应该引入
- 用户明确需要, 例如watchcat
- 内聚原则, 与服务有关的整体配置应该在同文件或者同目录完成所有关联配置

## 命名约定

- 规则、段的 `name` 只用 ASCII，不用中文：nuci 的 diff 会把非 ASCII 值按字节显示成乱码，`just router::preview` 就会永远多出一条「变更」（下发的值本身是对的）

## 机型相关的值

- 射频的 `band`、`path`、LAN 口名、WAN 口设备名、热点的 sta 设备名都集中在 `hardware.nix`，换路由器时只改它
- 它是纯数据，由 `network/` 下的文件 `import`，不在 `default.nix` 的 `imports` 里
