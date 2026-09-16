{
  config,
  lib,
  pkgs,
  mylib,
  ...
}:
let
  scriptsDir = ./tinycast;

  # 自动扫描 tinycast 目录下的全部 .sh 脚本并构建为 CLI 包
  scriptFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".sh" name) (
    builtins.readDir scriptsDir
  );

  basePackages = lib.mapAttrs' (
    fileName: _:
    let
      name = lib.removeSuffix ".sh" fileName;
    in
    lib.nameValuePair name (
      pkgs.writeShellScriptBin name (builtins.readFile (scriptsDir + "/${fileName}"))
    )
  ) scriptFiles;

  # 显示器输入源预设别名，方便命令行直接一键调用
  displayPresets = {
    display-switch-dp = "17";
    display-switch-tv = "18";
    display-switch-mio = "15";
  };

  presetPackages = lib.mapAttrsToList (
    name: source:
    pkgs.writeShellScriptBin name ''
      exec ${lib.getExe basePackages.display-switch} "${source}"
    ''
  ) displayPresets;

  # 基于命令名称生成确定性标准 UUID (8-4-4-4-12)
  mkUUID =
    name:
    let
      h = builtins.hashString "sha256" name;
    in
    "${builtins.substring 0 8 h}-${builtins.substring 8 4 h}-${builtins.substring 12 4 h}-${builtins.substring 16 4 h}-${builtins.substring 20 12 h}";

  # 原生 App 快捷键 (直连 Bundle ID，双向 Toggle：前台隐藏/后台唤起)
  appHotkeys = {
    "alt-f" = "com.apple.finder";
    "alt-w" = "com.tencent.xinWeChat";
    "alt-c" = "dev.zed.Zed";
    "alt-shift-enter" = "net.kovidgoyal.kitty";
  };

  # 声明需要在 Tinycast 启动器中直接搜索和调用的自定义命令
  commands = [
    {
      name = "Helium (Debug)";
      command = ''open -a "Helium" --args "--remote-debugging-port=9333"'';
      iconSymbol = "globe";
      hotkey = "alt-b";
    }
    {
      name = "New Kitty Window";
      command = lib.getExe basePackages.new-kitty;
      iconSymbol = "terminal";
    }
    {
      name = "写出剪贴板内容";
      command = lib.getExe basePackages.pb-type;
      iconSymbol = "keyboard";
    }
    {
      name = "显示器切到 DP (sakamoto)";
      command = "${lib.getExe basePackages.display-switch} 17";
      iconSymbol = "display";
    }
    {
      name = "显示器切到 HDMI1 (tv)";
      command = "${lib.getExe basePackages.display-switch} 18";
      iconSymbol = "tv";
    }
    {
      name = "显示器切到 HDMI2 (mio)";
      command = "${lib.getExe basePackages.display-switch} 15";
      iconSymbol = "display";
    }
  ];

  hotkeyedCommands = builtins.filter (c: c ? hotkey) commands;

  # 生成 targets.darwin.defaults 所需的偏好字典 (快捷键使用 mylib.darwinKeyCombo 统一换算)
  tinycastDefaults =
    (lib.mapAttrs' (
      chord: bundleID: lib.nameValuePair "hotkey.app.${bundleID}" (mylib.darwinKeyCombo chord)
    ) appHotkeys)
    // {
      boundAppBundleIDs = builtins.attrValues appHotkeys;
    }
    // (lib.listToAttrs (
      map (cmd: {
        name = "hotkey.customCommand.${lib.toLower (mkUUID cmd.name)}";
        value = mylib.darwinKeyCombo cmd.hotkey;
      }) hotkeyedCommands
    ))
    // {
      boundCustomCommandIDs = map (cmd: lib.toLower (mkUUID cmd.name)) hotkeyedCommands;
      customCommandsEnabled = true;
      customCommandsShowInLauncher = true;
    };
  managedCommands = map (cmd: {
    id = mkUUID cmd.name;
    inherit (cmd) name command iconSymbol;
  }) commands;

  # 原生 Swift 同步器：直接操作 Tinycast 的 UserDefaults，无外部 shell 工具管道转换
  syncScript = pkgs.writeText "sync-tinycast.swift" ''
    import Foundation

    guard let defaults = UserDefaults(suiteName: "com.tinycast.app") else { exit(1) }

    let managedJSON = CommandLine.arguments[1]
    guard let managedData = managedJSON.data(using: .utf8),
          let managedList = try? JSONSerialization.jsonObject(with: managedData) as? [[String: Any]]
    else { exit(1) }

    let managedIDs = Set(managedList.compactMap { $0["id"] as? String })

    var currentList: [[String: Any]] = []
    if let existingData = defaults.data(forKey: "customCommands"),
       let decoded = try? JSONSerialization.jsonObject(with: existingData) as? [[String: Any]] {
        currentList = decoded.filter {
            guard let id = $0["id"] as? String else { return true }
            return !managedIDs.contains(id)
        }
    }

    currentList.append(contentsOf: managedList)

    guard let mergedData = try? JSONSerialization.data(withJSONObject: currentList) else { exit(1) }
    if defaults.data(forKey: "customCommands") != mergedData {
        defaults.set(mergedData, forKey: "customCommands")
    }

    defaults.set(true, forKey: "customCommandsEnabled")
    defaults.set(true, forKey: "customCommandsShowInLauncher")
  '';
in
{
  home.packages = (builtins.attrValues basePackages) ++ presetPackages;
  # 原生接管快捷键与命令索引映射
  targets.darwin.defaults."com.tinycast.app" = tinycastDefaults;

  # 软链接脚本目录至 ~/.config/tinycast/scripts，便于调试
  xdg.configFile."tinycast/scripts" = {
    force = true;
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/darwin/scripts/tinycast";
  };

  # 激活时同步到 Tinycast，使其在启动器中立即可被搜索调用
  home.activation.tinycastCustomCommands = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    /usr/bin/swift ${syncScript} '${builtins.toJSON managedCommands}'
  '';
}
