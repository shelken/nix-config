{
  lib,
  mylib,
  config,
  myvars,
  ...
}:
let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    types
    ;
  inherit (mylib) mkBoolOpt;
  cfg = config.shelken.tools.autoinputswitch;

  # TypeSwitch 输入法策略常量
  fixed = id: {
    fixed = {
      inputMethodId = id;
    };
  };
  followLast = {
    followLast = { };
  };

  chinese = fixed "im.rime.inputmethod.Squirrel.Hans";
  english = fixed "com.apple.keylayout.ABC";

  # 合并后的 appRules（取 typeswitch 和 inputsourcepro 的并集）
  appRules = {
    # English
    "com.apple.finder" = english;
    "com.apple.Spotlight" = english;
    "com.microsoft.VSCode" = english;
    "dev.zed.Zed" = english;
    "dev.zed.Zed-Preview" = english;
    "com.conductor.app" = english;
    "com.apple.dt.Xcode" = english;
    "net.kovidgoyal.kitty" = english;
    "tv.parsec.www" = english;
    "com.apple.ScreenSharing" = english;
    "com.apple.Safari" = english;
    "com.google.Chrome" = english;
    "net.imput.helium" = english;
    # Chinese
    "com.apple.Notes" = chinese;
    "com.tencent.xinWeChat" = chinese;
    "md.obsidian" = chinese;
    "ru.keepcoder.Telegram" = chinese;
    "com.kangfenmao.CherryStudio" = chinese;
    "com.openai.chat" = chinese;
    "com.anthropic.claudefordesktop" = chinese;
    "com.apple.MobileSMS" = chinese;
    "com.apple.systempreferences" = chinese;
    "com.yetone.alma" = chinese;
    # 记住上次
    "com.muxy.app" = followLast;
  };

  # 传递给 jq --argjson 合并已有 app-rules.json
  desiredJSON = builtins.toJSON appRules;
in
{
  options.shelken.tools.autoinputswitch = {
    enable = mkBoolOpt false "是否启用自动输入法切换";
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
      homebrew.casks = [ "shelken/tap/typeswitch" ];

      # 变更原因: TypeSwitch >=0.5.x 读取 app-rules.json，不再使用 defaults
      # 仅在 TypeSwitch 已启动并生成 app-rules.json 后才合并写入；首次部署不创建
      home-manager.users.${myvars.username}.home.activation.typeswitchRules = ''
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

      launchd.user.agents.autoinputswitch = {
        command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
        serviceConfig.RunAtLoad = true;
      };
    })
    (mkIf (cfg.enable && cfg.app == "inputsourcepro") {
      homebrew.casks = [ "shelken/tap/input-source-pro-beta" ];

      home-manager.users.${myvars.username}.home.file.".config/inputsourcepro/config.json".text =
        let
          # 仅保留 fixed 策略，提取 inputMethodId 作为平坦字符串
          fixedRules = lib.filterAttrs (_: v: v ? fixed) appRules;
          inputsourceproRules = builtins.mapAttrs (_: v: v.fixed.inputMethodId) fixedRules;
        in
        builtins.toJSON inputsourceproRules;

      system.defaults.CustomUserPreferences."space.ooooo.Input-Source-Pro.Beta" = {
        isRestorePreviouslyUsedInputSource = false;
        isActiveWhenSwitchApp = false;
      };
    })
  ];
}
