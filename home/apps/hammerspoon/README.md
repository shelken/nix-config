# hammerspoon

## 组件

- 窗口管理器（PaperWM）(替代 aerospace)
- 常用 app 快捷键 (替代 aerospace)
- 根据 app 自动切换输入法（目前为 `ABC|RIME`）(替代 typeswitch)

## 使用

窗口管理与其他没有兼容如有必要，先关闭yabi aerospace配置

配置

```nix
config.shelken.tools.hammerspoon.enable = true;
# config.shelken.wm.aerospace.enable = false
# config.shelken.tools.typeswitch.enable = false
# config.shelken.wm.yabi.enable = false
```
