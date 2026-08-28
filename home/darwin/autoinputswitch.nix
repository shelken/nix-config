# TypeSwitch / Input Source Pro 的用户态配置文件（home 层）。
#
# 为什么在 home 层：app-rules 合并与 config.json 是用户家目录状态，
# 由 darwin 模块注入 home-manager.users 时，独立 HM 入口（just hm）
# 切换会清理/漂移这些 home 状态。与 hosts/<host>/tasks 的 user 任务
# 同理，用户态配置归两个 HM 入口共同持有。
#
# 开关与 darwin 层（modules/darwin/apps/tools/autoinputswitch.nix）
# 同名同值，需在 hosts/<host>/home.nix 镜像开启。
{
  lib,
  mylib,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    ;
  cfg = config.shelken.tools.autoinputswitch;

  # TypeSwitch 输入法策略常量
  fixed = id: {
    fixed = {
      inputMethodId = id;
    };
  };
  none = {
    none = { };
  };

  chinese = fixed "im.rime.inputmethod.Squirrel.Hans";
  english = fixed "com.apple.keylayout.ABC";

  # 合并后的 appRules（取 typeswitch 和 inputsourcepro 的并集）
  # none 必须显式写入 desired：activation 只 merge，删 key 不会清掉旧 strategy
  appRules = {
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
  };

  # 传递给 jq --argjson 合并已有 app-rules.json
  desiredJSON = builtins.toJSON appRules;
in
{
  options.shelken.tools.autoinputswitch = {
    enable = mylib.mkBoolOpt false "是否启用自动输入法切换（与 darwin 层开关同名，需同步）";
    app = mkOption {
      type = types.enum [
        "typeswitch"
        "inputsourcepro"
      ];
      default = "typeswitch";
      description = "选择使用哪个自动输入法切换软件";
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.app == "typeswitch") {
      # 变更原因: TypeSwitch >=0.5.x 读取 app-rules.json，不再使用 defaults
      # 仅在 TypeSwitch 已启动并生成 app-rules.json 后才合并写入；首次部署不创建
      home.activation.typeswitchRules = ''
        file="$HOME/Library/Application Support/top.ygsgdbd.TypeSwitch/app-rules.json"
        if [ -f "$file" ]; then
          now=$(( $(date +%s) - 978307200 ))
          jq --argjson desired '${desiredJSON}' --argjson now "$now" '
            .rules = (.rules // {}) |
            reduce ($desired | to_entries[]) as $e (.;
              .rules[$e.key] |= (
                (. // {}) *
                {
                  bundleId: $e.key,
                  lastKnownName: (.lastKnownName // "Unknown"),
                  createdAt: (.createdAt // $now),
                  updatedAt: $now
                }
                | .strategy = $e.value
              )
            )
          ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
        fi
      '';
    })
    (mkIf (cfg.enable && cfg.app == "inputsourcepro") {
      home.file.".config/inputsourcepro/config.json".text =
        let
          # 仅保留 fixed 策略，提取 inputMethodId 作为平坦字符串
          fixedRules = lib.filterAttrs (_: v: v ? fixed) appRules;
          inputsourceproRules = builtins.mapAttrs (_: v: v.fixed.inputMethodId) fixedRules;
        in
        builtins.toJSON inputsourceproRules;
    })
  ];
}
