# Hammerspoon

提供基于 Lua 的 macOS 桌面辅助与窗口管理能力，作为可选功能按需导入

## 组件与功能

- **平铺窗口管理（PaperWM）**：基于滚动画布模型的窗口管理实现，作为 AeroSpace 的备选方案
- **应用快捷键绑定**：全局快速唤醒与切换指定 App
- **[自动输入法切换](config/input-change.lua)**：依据当前前台 App 自动在英文与 Rime 输入法间切换，可作为 TypeSwitch 的备选

## 启用与配置

Hammerspoon 属于可选功能，未默认挂载到任何系统角色；若要启用需在主机配置中显式导入：

```nix
# hosts/<主机>/default.nix：导入系统侧模块
imports = [ self.modules.darwin.hammerspoon ];

# hosts/<主机>/home.nix：启用 Hammerspoon 内部的窗口管理配置（HM 侧选项）
shelken.tools.hammerspoon.wm.enable = true;
```

注意：系统默认的平铺窗口管理器为 AeroSpace（由 `shelken.wm.manager` 控制），启用 Hammerspoon 的窗口管理前需确认避免快捷键冲突；另外当前 `home.nix` 中的窗口管理串接逻辑存在历史未验证项，开启 `wm.enable` 前建议先核验配置实现
