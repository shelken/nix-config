{
  flake.modules.homeManager.autoinputswitch =
    { lib, osConfig, ... }:
    let
      inherit (osConfig.shelken.tools.autoinputswitch) app;
      appRules = import ./_app-rules.nix;
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
