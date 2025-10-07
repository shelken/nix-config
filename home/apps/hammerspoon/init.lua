hs.hotkey.bind({"cmd", "alt", "ctrl"}, "W", function()
  hs.alert.show("Hello World!")
end)
hs.hotkey.bind({"cmd", "alt", "ctrl"}, "R", function()
    hs.reload()
end)
hs.alert.show("Hammerspoon reloaded!")

-- 需要提前安装spooninstall
-- mkdir -p ~/.hammerspoon/Spoons && \
-- curl -L https://github.com/Hammerspoon/Spoons/raw/master/Spoons/SpoonInstall.spoon.zip -o ~/.hammerspoon/SpoonInstall.spoon.zip && \
-- unzip -o ~/.hammerspoon/SpoonInstall.spoon.zip -d ~/.hammerspoon/Spoons/ && \
-- rm ~/.hammerspoon/SpoonInstall.spoon.zip

-- 加载 SpoonInstall
hs.loadSpoon("SpoonInstall")

-- 启动 IPC 服务器，允许hs命令行工具通信
require("hs.ipc")

-- 引用
require("config.paperwm") -- 窗口管理
require("config.app-shortcut") -- 快捷键
require("config.test") -- 
require("config.input-change") -- 
