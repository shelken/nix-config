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

窗口管理与其他没有兼容如有必要，先关闭yabi aerospace配置

配置

```nix
config.shelken.tools.hammerspoon.enable = true;
config.shelken.tools.hammerspoon.wm.enable = true;
# config.shelken.wm.aerospace.enable = false
# config.shelken.tools.typeswitch.enable = false
# config.shelken.wm.yabi.enable = false
```
