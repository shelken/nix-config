# Helium

浏览器本体由 `darwin.nix` 经 brew cask 安装，随 `gui` 角色分发；受管扩展由 `home.nix` 声明。

## 受管扩展

`home.nix` 往 `~/Library/Application Support/net.imput.helium/External Extensions/<id>.json` 写声明文件。该目录属于整个数据目录，所有 profile 启动时都会读取，缺哪个就在自己的 `Extensions/` 下载安装哪个。

- 扩展不跨 profile 共享：每个 profile 各下载、各存一份，没有共享缓存（macOS 上 Chromium 用的是空缓存）。
- `external_update_url` 必须是 Helium 的占位符地址。写 Google 原地址时请求被拦截，扩展不会安装（Helium 0.21 实测）。
- 新建的 profile 要先完成首次引导里的服务同意（`helium.services.user_consented`），声明的扩展才会安装。
- 外部安装的扩展可能初始为禁用，需要在扩展页确认启用。
- 在某个 profile 手动卸载一个外部扩展后，Chromium 记入该 profile 的 `extensions.external_uninstalls`，之后不再重装（源码依据，未做界面实测）。
- 从清单删掉某一项，该扩展会在所有 profile 被卸载。

## 同步扩展设置

`helium-sync-ext` 把 Default 里清单扩展的 `Local Extension Settings/<id>/` 复制到其他 `Profile N`。扩展设置按「扩展 ID + profile」各存一份，没有声明式入口，所以只能复制。

- 先退出 Helium。脚本读 `SingletonLock` 判断，运行中会拒绝执行。
- 单向覆盖：目标 profile 里这些扩展原有的设置会被替换。
- 目标是有 `Preferences` 的 `Profile N`。`System Profile` 不算。
- 只复制 `storage.local`。用 IndexedDB 存设置的扩展不在范围内，未测试。
- 复制后重启，扩展读到的是 Default 的设置（用 GeoSpoof 在临时 profile 实测）。
- 清单里的扩展默认全部同步。Default 里没有存储的扩展会跳过。
