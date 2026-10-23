-- 当选中某窗口按下 ctrl+command+. 时会显示应用的路径、名字等信息
hs.hotkey.bind({'ctrl', 'cmd'}, ".", function()
    hs.pasteboard.setContents(hs.window.focusedWindow():application():bundleID())
    hs.alert.show("App bundleID:    " .. hs.window.focusedWindow():application():bundleID() .. "\nApp name:      " ..
                      hs.window.focusedWindow():application():name() .. "\nIM source id:  " ..
                      hs.keycodes.currentSourceID() .. "\nIM Layout:  " ..
                      hs.keycodes.currentLayout() .. "\nIM Method:  " ..
                      tostring(hs.keycodes.currentMethod()) .. "\nFront App id:  " ..
                      hs.application.frontmostApplication():bundleID(), hs.alert.defaultStyle, hs.screen.mainScreen(), 5)
end)

-- -- activated 时切换到指定的输入法，deactivated 时恢复之前的状态
-- lastID = ""

-- -- 这里指定中文和英文输入法的 ID
input_sources = {
    chinese = "im.rime.inputmethod.Squirrel.Hans",
    english = "com.apple.keylayout.ABC"
    -- chinese = "com.apple.inputmethod.SCIM.ITABC",
    -- english = "com.apple.keylayout.US"
}
input_method_layout = {
    [input_sources.chinese] = "Squirrel - Simplified",
    [input_sources.english] = "ABC"
}

-- hs.keycodes.currentSourceID 切换有问题(从ABC手动换回RIME会出现rime没有正常加载只能输出字母)，使用setmethod或setlayout来操作。
local function Chinese()
    -- print("切换到中文")
    -- hs.keycodes.currentSourceID(input_sources.chinese)
    hs.keycodes.setLayout(input_method_layout[input_sources.english])
    hs.keycodes.setMethod(input_method_layout[input_sources.chinese])
end
local function English()
    -- print("切换到英文")
    -- hs.keycodes.currentSourceID(input_sources.english)
    hs.keycodes.setLayout(input_method_layout[input_sources.english])
    -- hs.keycodes.setMethod(nil)
end

local function set_app_input_method(app_name, set_input_method_function, event)
    event = event or hs.window.filter.windowFocused

    hs.window.filter.new(app_name):subscribe(event, function()
      -- print("event: " .. tostring(event))  
      set_input_method_function()
    end)
end

-- 检查名字：直接在Raycast中查看

-- windowFocused > English
set_app_input_method({
  -- 'Raycast',
  -- 'Spotlight',
  -- '聚焦',
  -- 'Finder',
  '访达',
  'kitty',
  'Code',
  'Parsec',
}, English)

-- windowFocused > Chinese
set_app_input_method({
  "WeChat",
  "微信",
  "Telegram",
  "Notes",
  "备忘录",
  "Obsidian",
  "Cherry Studio",
  "ChatGPT",

  'Helium',
  'Google Chrome',
  'Safari',
}, Chinese)


-- windowCreated > English
set_app_input_method({
  'Raycast',
  'Spotlight',
  '聚焦',
}, English, 
{
  hs.window.filter.windowCreated,
})

-- 切换中英输入法
local function toggle_input_source()
    local current_source_id = hs.keycodes.currentSourceID()
    if current_source_id == input_sources.chinese then
        English()
    else
        Chinese()
    end
end

hs.hotkey.bind({"ctrl"}, "space", toggle_input_source)