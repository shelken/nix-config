# router-mine

## 引入原则

- 适用于 OpenWrt 及其衍生系统，更换路由器时可直接迁移
- 收录路由器核心职责必需的配置（防火墙、DHCP、DNS）、与 `home-ops` 联动配置以及明确需要的服务（如 watchcat）
- 同一服务的关联配置内聚在同一文件或同一目录

## 命名约定

- 规则与段的 `name` 只用 ASCII，不用中文：nuci diff 会按字节把非 ASCII 显示为乱码，导致 `just router::preview` 始终报出伪变更
