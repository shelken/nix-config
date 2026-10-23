# hammerspoon

## 问题

- 窗口管理器paperwm不能很好解决窗口切换，例如窗口一直漂移和光标到哪个窗口就整个横移
- 无法一键去除所有快捷键进入远程模式，且与parsec不能很好配合
- 目前aerospace的问题在于大小调整和layout调整的便携性。

## 组件

- 窗口管理器（PaperWM）(替代 aerospace)
- 常用 app 快捷键 (替代 aerospace)
- [根据 app 自动切换输入法](config/input-change.lua)（目前为 `ABC|RIME`）(替代 typeswitch)

## 使用

窗口管理与其他没有兼容如有必要，需注意窗口管理器冲突（当前默认平铺窗口管理器为 aerospace，由 `shelken.wm.manager` 控制）

配置

```nix
imports = [ config.flake.modules.darwin.hammerspoon ];
shelken.tools.hammerspoon.wm.enable = true;
# 注意：窗口管理器二选一选项 shelken.wm.manager 默认启用 aerospace
```
