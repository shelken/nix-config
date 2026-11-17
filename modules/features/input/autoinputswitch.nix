# 自动输入法切换：所在角色的主机即启用；
# 主机可设 shelken.tools.autoinputswitch.app 切换软件，HM 部分经 osConfig 读取同一值
{ config, ... }:
{
  # 加入哪一层只在这里声明，主机不直接导入具体功能
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.autoinputswitch ];

  flake.modules.darwin.autoinputswitch =
    { lib, config, ... }:
    let
      inherit (config.shelken.tools.autoinputswitch) app;
    in
    {
      options.shelken.tools.autoinputswitch.app = lib.mkOption {
        type = lib.types.enum [
          "typeswitch"
          "inputsourcepro"
        ];
        default = "typeswitch";
        description = "选择使用哪个自动输入法切换软件";
      };

      config = lib.mkMerge [
        (lib.mkIf (app == "typeswitch") {
          homebrew.casks = [ "shelken/tap/typeswitch" ];

          launchd.user.agents.autoinputswitch = {
            command = ''"/Applications/TypeSwitch.app/Contents/MacOS/TypeSwitch"'';
            serviceConfig.RunAtLoad = true;
          };
        })
        (lib.mkIf (app == "inputsourcepro") {
          homebrew.casks = [ "shelken/tap/input-source-pro-beta" ];

          system.defaults.CustomUserPreferences."space.ooooo.Input-Source-Pro.Beta" = {
            isRestorePreviouslyUsedInputSource = false;
            isActiveWhenSwitchApp = false;
          };
        })
      ];
    };

  flake.modules.homeManager.autoinputswitch =
    { lib, osConfig, ... }:
    let
      inherit (osConfig.shelken.tools.autoinputswitch) app;
      # TypeSwitch / Input Source Pro 共用的应用输入法规则（取两者并集）
      appRules =
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
        };
      # 传递给 jq --argjson 合并已有 app-rules.json
      desiredJSON = builtins.toJSON appRules;
    in
    lib.mkMerge [
      (lib.mkIf (app == "typeswitch") {
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
      (lib.mkIf (app == "inputsourcepro") {
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
