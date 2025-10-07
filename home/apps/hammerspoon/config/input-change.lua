local input_sources = {
    chinese = "im.rime.inputmethod.Squirrel.Hans",
    english = "com.apple.keylayout.ABC",
}

local function switch_input_source(source_id, source_name)
    if hs.keycodes.currentSourceID() ~= source_id then
        print("切换输入法为 " .. source_name)
        hs.keycodes.currentSourceID(source_id)
    end
end

local function Chinese()
    switch_input_source(input_sources.chinese, "RIME")
end

local function English()
    switch_input_source(input_sources.english, "ABC")
end

local function set_app_input_method(app_name, set_input_method_function, event)
    event = event or hs.window.filter.windowFocused

    hs.window.filter.new(app_name):subscribe(event, function()
      -- print("event: " .. tostring(event))  
      set_input_method_function()
    end)
end

-- appInputMethodSettings =     {
--         "com.microsoft.VSCode" = "com.apple.keylayout.ABC";
--         "com.raycast.macos" = "com.apple.keylayout.ABC";
--         "md.obsidian" = "im.rime.inputmethod.Squirrel.Hans";
--         "net.imput.helium" = "im.rime.inputmethod.Squirrel.Hans";
--         "net.kovidgoyal.kitty" = "com.apple.keylayout.ABC";
--         "tv.parsec.www" = "com.apple.keylayout.ABC";
--     };

-- windowFocused > English
set_app_input_method({
  -- 'Raycast',
  -- 'Spotlight',
  -- '聚焦',
  -- 'Finder',
  '访达',
  'kitty',
  'Code',
  'Helium',
  'Google Chrome',
  'Safari',
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
