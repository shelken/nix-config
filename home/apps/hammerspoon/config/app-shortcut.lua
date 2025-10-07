local function toggleApp(name)
  local app = hs.application.find(name)
  if not app or app:isHidden() then
    hs.application.launchOrFocus(name)
  elseif hs.application.frontmostApplication() ~= app then
    app:activate()
  else
    app:hide()
  end
end

hs.hotkey.bind({"alt"}, "B", function()
  hs.application.launchOrFocus("Helium")
end)
hs.hotkey.bind({"alt"}, "C", function()
  hs.application.launchOrFocus("Visual Studio Code")
end)
hs.hotkey.bind({"alt"}, "F", function()
  hs.application.launchOrFocus("Finder")
end)
hs.hotkey.bind({"alt"}, "K", function()
  -- local app = hs.application.get("kitty")
    -- if app then
    --     if not app:mainWindow() then
    --         app:selectMenuItem({"kitty", "New OS window"})
    --     elseif app:isFrontmost() then
    --         app:hide()
    --     else
    --         app:activate()
    --     end
    -- else
    --     toggleApp("kitty")
    -- end
    hs.application.launchOrFocus("kitty")
end)
hs.hotkey.bind({"alt", "shift"}, "K", function()
  -- hs.alert.show("切换 kitty 悬浮窗")
  local cmd = "/Applications/kitty.app/Contents/MacOS/kitten"
  hs.task.new(cmd, 
    function() print("结束") end, 
    function() return false end, 
    {"quick-access-terminal", 
    "-o", "edge=center-sized", -- center-sized
    -- "-o", "margin_left=150",
    "-o", "start_as_hidden=no",
    "-o", "hide_on_focus_loss=yes",
    "-o", "lines=35",
    "-o", "columns=112",
    "-o", "background_opacity=0.55",
  }):start()
end)
hs.hotkey.bind({"alt"}, "W", function()
  hs.application.launchOrFocus("WeChat")
end)
return {}