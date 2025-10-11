PaperWM = hs.loadSpoon("PaperWM")
PaperWM.screen_margin = 16
PaperWM.window_gap = {
    top = 8,
    bottom = 8,
    left = 6,
    right = 6
}

PaperWM:bindHotkeys({
    -- switch to a new focused window in tiled grid
    focus_left = {{"alt"}, "left"},
    focus_right = {{"alt"}, "right"},
    focus_up = {{"alt"}, "up"},
    focus_down = {{"alt"}, "down"},

    -- switch windows by cycling forward/backward
    -- (forward = down or right, backward = up or left)
    -- focus_prev = {{"alt", "cmd"}, "k"},
    -- focus_next = {{"alt", "cmd"}, "j"},

    -- move windows around in tiled grid
    swap_left = {{"alt", "ctrl"}, "left"},
    swap_right = {{"alt", "ctrl"}, "right"},
    swap_up = {{"alt", "ctrl"}, "up"},
    swap_down = {{"alt", "ctrl"}, "down"},

    -- alternative: swap entire columns, rather than
    -- individual windows (to be used instead of
    -- swap_left / swap_right bindings)
    swap_column_left = {{"alt", "ctrl", "shift"}, "left"},
    swap_column_right = {{"alt", "ctrl", "shift"}, "right"},

    -- position and resize focused window
    center_window = {{"alt", "cmd"}, "c"},
    full_width = {{"alt", "ctrl"}, "return"},
    -- cycle_width = {{"alt", "cmd"}, "r"},
    -- reverse_cycle_width = {{"ctrl", "alt", "cmd"}, "r"},
    -- cycle_height = {{"alt", "cmd", "shift"}, "r"},
    -- reverse_cycle_height = {{"ctrl", "alt", "cmd", "shift"}, "r"},

    -- increase/decrease width
    -- increase_width = {{"alt", "shift"}, "="},
    -- decrease_width = {{"alt", "shift"}, "-"},
    -- increase_height = {{"alt", "shift", "cmd"}, "="},
    -- decrease_height = {{"alt", "shift", "cmd"}, "-"},
    increase_width = {{"alt", "shift", "cmd"}, "right"},
    decrease_width = {{"alt", "shift", "cmd"}, "left"},
    increase_height = {{"alt", "shift", "cmd"}, "up"},
    decrease_height = {{"alt", "shift", "cmd"}, "down"},

    -- move focused window into / out of a column
    slurp_in = {{"alt", "cmd"}, "i"},
    barf_out = {{"alt", "cmd"}, "o"},

    -- move the focused window into / out of the tiling layer
    -- toggle_floating = {{"alt", "cmd", "shift"}, "escape"},
    toggle_floating = {{"alt", "ctrl"}, "f"},

    -- focus the first / second / etc window in the current space
    -- focus_window_1 = {{"cmd", "shift"}, "1"},
    focus_window_1 = {{"alt"}, "1"},
    focus_window_2 = {{"alt"}, "2"},
    focus_window_3 = {{"alt"}, "3"},
    focus_window_4 = {{"alt"}, "4"},
    focus_window_5 = {{"alt"}, "5"},
    focus_window_6 = {{"alt"}, "6"},
    focus_window_7 = {{"alt"}, "7"},
    focus_window_8 = {{"alt"}, "8"},
    focus_window_9 = {{"alt"}, "9"},

    -- switch to a new Mission Control space
    switch_space_l = {{"alt", "cmd"}, ","},
    switch_space_r = {{"alt", "cmd"}, "."},
    switch_space_1 = {{"alt", "cmd"}, "1"},
    switch_space_2 = {{"alt", "cmd"}, "2"},
    switch_space_3 = {{"alt", "cmd"}, "3"},
    switch_space_4 = {{"alt", "cmd"}, "4"},
    switch_space_5 = {{"alt", "cmd"}, "5"},
    switch_space_6 = {{"alt", "cmd"}, "6"},
    switch_space_7 = {{"alt", "cmd"}, "7"},
    switch_space_8 = {{"alt", "cmd"}, "8"},
    switch_space_9 = {{"alt", "cmd"}, "9"},

    -- move focused window to a new space and tile
    move_window_1 = {{"alt", "shift"}, "1"},
    move_window_2 = {{"alt", "shift"}, "2"},
    move_window_3 = {{"alt", "shift"}, "3"},
    move_window_4 = {{"alt", "shift"}, "4"},
    move_window_5 = {{"alt", "shift"}, "5"},
    move_window_6 = {{"alt", "shift"}, "6"},
    move_window_7 = {{"alt", "shift"}, "7"},
    move_window_8 = {{"alt", "shift"}, "8"},
    move_window_9 = {{"alt", "shift"}, "9"}
})

-- local modal = hs.hotkey.modal.new({"alt", "shift", "cmd"}, "return", "new modal")
-- modal:bind({}, "h", "new modal", function()
-- end)
-- modal:bind({}, "escape", "exit modal", function()
--     modal:exit()
-- end)

-- 浮动窗口
-- for _, win in ipairs(hs.window.allWindows()) do  print("ID: " .. win:id() .. ", App: " .. win:application():name() .. ", Title: " .. win:title() .. ", subRole: " .. win:subrole() .. ", role: " .. win:role() .. ", isStand: " .. tostring(win:isStandard()))end
PaperWM.window_filter:rejectApp("BetterDisplay")
PaperWM.window_filter:rejectApp("App Store")
PaperWM.window_filter:rejectApp("IINA")
PaperWM.window_filter:rejectApp("Motrix")
PaperWM.window_filter:rejectApp("FlClash")
PaperWM.window_filter:rejectApp("Raycast")
PaperWM.window_filter:rejectApp("Hammerspoon")
PaperWM.window_filter:rejectApp("Hammerspoon Console")

PaperWM.window_filter:rejectApp("Activity Monitor")
PaperWM.window_filter:rejectApp("活动监视器")

PaperWM.window_filter:rejectApp("访达")
PaperWM.window_filter:rejectApp("Finder")

PaperWM.window_filter:rejectApp("System Settings")
PaperWM.window_filter:rejectApp("系统设置")

PaperWM.window_filter:rejectApp("Photos")
PaperWM.window_filter:rejectApp("照片")

PaperWM.window_filter:rejectApp("Reminders")
PaperWM.window_filter:rejectApp("提醒事项")

PaperWM.window_filter:rejectApp("Messages")
PaperWM.window_filter:rejectApp("信息")

PaperWM.window_filter:rejectApp("Music")
PaperWM.window_filter:rejectApp("音乐")
PaperWM.window_filter:rejectApp("Audirvana")

PaperWM.window_filter:rejectApp("TextEdit")
PaperWM.window_filter:rejectApp("文本编辑")

-- PaperWM.window_filter:rejectApp("WeChat")
-- PaperWM.window_filter:rejectApp("微信")
PaperWM:start()
return {}
