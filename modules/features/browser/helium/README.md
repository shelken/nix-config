# Helium

浏览器本体（经 brew cask 随 `gui` 分发）与受管扩展均由 `default.nix` 声明，受管扩展声明写入 `~/Library/Application Support/net.imput.helium/External Extensions/<id>.json`

## 受管扩展行为

- 扩展不跨 profile 共享（macOS 上 Chromium 无共享缓存）；新建 profile 需先同意引导服务（`helium.services.user_consented`）才会安装
- 外部扩展初始可能为禁用，需手动启用；在某 profile 手动卸载后会记入 `extensions.external_uninstalls` 不再重装（源码依据），从清单移除则在所有 profile 卸载

## 同步扩展设置

`helium-sync-ext` 把 Default 里清单扩展的 `Local Extension Settings/<id>/` 复制到其他 `Profile N`（需先退出 Helium）

- 单向覆盖目标 profile 原有设置，重启后生效
- 只复制 `storage.local`，用 IndexedDB 存设置的扩展不在范围内（未测试）
