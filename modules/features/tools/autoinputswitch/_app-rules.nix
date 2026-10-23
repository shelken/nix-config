# TypeSwitch / Input Source Pro 共用的应用输入法规则（取两者并集）。
# 下划线前缀让 import-tree 跳过此文件，只由 home.nix 按路径引用。
let
  fixed = id: {
    fixed = {
      inputMethodId = id;
    };
  };
  # none 必须显式写入 desired：activation 只 merge，删 key 不会清掉旧 strategy
  none = {
    none = { };
  };

  chinese = fixed "im.rime.inputmethod.Squirrel.Hans";
  english = fixed "com.apple.keylayout.ABC";
in
{
  # English（编码/终端：跨中文 App 切回来时强制 ABC）
  "com.apple.Spotlight" = english;
  "com.microsoft.VSCode" = english;
  "dev.zed.Zed" = english;
  "dev.zed.Zed-Preview" = english;
  "com.conductor.app" = english;
  "com.apple.dt.Xcode" = english;
  "net.kovidgoyal.kitty" = english;
  "tv.parsec.www" = english;
  "com.google.Chrome" = english;
  "net.imput.helium" = english;
  # Chinese（聊天/笔记）
  "com.apple.Notes" = chinese;
  "com.tencent.xinWeChat" = chinese;
  "md.obsidian" = chinese;
  "ru.keepcoder.Telegram" = chinese;
  "com.kangfenmao.CherryStudio" = chinese;
  "com.openai.chat" = chinese;
  "com.anthropic.claudefordesktop" = chinese;
  "com.apple.MobileSMS" = chinese;
  "com.yetone.alma" = chinese;
  # 不强制：减少无意义边界切换 / 焦点抖动放大
  "com.apple.ScreenSharing" = none; # 与本地键盘源同步叠加
  "com.apple.finder" = none;
  "com.apple.Safari" = none; # 中英都写，不必钉死
  "com.apple.systempreferences" = none;
}
