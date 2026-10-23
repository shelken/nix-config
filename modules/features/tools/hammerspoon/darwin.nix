# Hammerspoon：macOS 自动化与窗口管理（可选功能，不加入角色）
{
  flake.modules.darwin.hammerspoon =
    { ... }:
    {
      homebrew.casks = [ "hammerspoon" ];
      system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
        "60" = {
          enabled = false;
        };
      };
    };
}
