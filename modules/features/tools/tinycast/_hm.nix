{
  config,
  lib,
  pkgs,
  mylib,
  ...
}:
let
  # scripts/*.sh 各自构建成同名 CLI
  scriptsDir = ./scripts;

  scripts =
    lib.mapAttrs'
      (
        fileName: _:
        let
          name = lib.removeSuffix ".sh" fileName;
        in
        lib.nameValuePair name (
          pkgs.writeShellScriptBin name (builtins.readFile (scriptsDir + "/${fileName}"))
        )
      )
      (
        lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".sh" name) (
          builtins.readDir scriptsDir
        )
      );

  # 显示器输入源：CLI 别名与启动器条目共用这一张表
  displayInputs = [
    {
      id = "dp";
      source = "17";
      label = "DP (sakamoto)";
      icon = "display";
    }
    {
      id = "tv";
      source = "18";
      label = "HDMI1 (tv)";
      icon = "tv";
    }
    {
      id = "mio";
      source = "15";
      label = "HDMI2 (mio)";
      icon = "display";
    }
  ];

  displaySwitch = lib.getExe scripts.display-switch;

  displayPackages = map (
    input:
    pkgs.writeShellScriptBin "display-switch-${input.id}" ''
      exec ${displaySwitch} "${input.source}"
    ''
  ) displayInputs;

  displayCommands = map (input: {
    name = "显示器切到 ${input.label}";
    command = "${displaySwitch} ${input.source}";
    iconSymbol = input.icon;
  }) displayInputs;

  # 启动器自定义命令；hotkey 只用于下面的 defaults，不进 App 的记录
  customCommands = [
    {
      name = "Helium (Debug)";
      command = ''open -a "Helium" --args "--remote-debugging-port=9333"'';
      iconSymbol = "globe";
      hotkey = "alt-b";
    }
    {
      name = "New Kitty Window";
      command = lib.getExe scripts.new-kitty;
      iconSymbol = "terminal";
    }
    {
      name = "写出剪贴板内容";
      command = lib.getExe scripts.pb-type;
      iconSymbol = "keyboard";
    }
  ]
  ++ displayCommands;

  # App 以命令 id 索引别名、收藏与快捷键，所以必须由名字生成稳定 UUID
  mkUUID =
    name:
    let
      h = builtins.hashString "sha256" name;
    in
    "${builtins.substring 0 8 h}-${builtins.substring 8 4 h}-${builtins.substring 12 4 h}-${builtins.substring 16 4 h}-${builtins.substring 20 12 h}";

  commandRecords = map (cmd: {
    id = mkUUID cmd.name;
    inherit (cmd) name command iconSymbol;
  }) customCommands;

  hotkeyedCommands = builtins.filter (cmd: cmd ? hotkey) customCommands;
  managedCommandIDs = map (cmd: lib.toLower (mkUUID cmd.name)) hotkeyedCommands;

  # 原生 App 快捷键：直连 Bundle ID，前景隐藏 / 后台唤起
  appHotkeys = {
    "alt-f" = "com.apple.finder";
    "alt-w" = "com.tencent.xinWeChat";
    "alt-c" = "dev.zed.Zed";
    "alt-shift-enter" = "net.kovidgoyal.kitty";
  };

  appHotkeyDefaults = lib.mapAttrs' (
    chord: bundleID: lib.nameValuePair "hotkey.app.${bundleID}" (mylib.darwinKeyCombo chord)
  ) appHotkeys;

  commandHotkeyDefaults = builtins.listToAttrs (
    map (cmd: {
      name = "hotkey.customCommand.${lib.toLower (mkUUID cmd.name)}";
      value = mylib.darwinKeyCombo cmd.hotkey;
    }) hotkeyedCommands
  );

  tinycastDefaults =
    appHotkeyDefaults
    // commandHotkeyDefaults
    // {
      boundAppBundleIDs = builtins.attrValues appHotkeys;
      boundCustomCommandIDs = managedCommandIDs;
      customCommandsEnabled = true;
      customCommandsShowInLauncher = true;
      # settings.json 镜像总开关：只有它为真，App 才读写下面那份文件
      settingsFileEnabled = true;
    };
in
{
  home.packages = builtins.attrValues scripts ++ displayPackages;

  targets.darwin.defaults."com.tinycast.app" = tinycastDefaults;

  # 脚本目录软链出去，便于直接调试
  xdg.configFile."tinycast/scripts" = mylib.mkConfigFile config scriptsDir;

  # settings.json 由 App 回写，必须软链到仓库内的可写源文件：非 liveEdit 主机会链到只读
  # 的 Store 路径，App 保存失败并报错
  xdg.configFile."tinycast/settings.json" = mylib.mkConfigFile config ./settings.json;

  # 自定义命令的内容不在 settings.json 里，只能由 activation 合并进 UserDefaults；
  # 排在 setDarwinDefaults 之后，避免两个步骤的写入顺序不明确
  home.activation.tinycastCustomCommands = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
    /usr/bin/swift ${./sync-commands.swift} '${builtins.toJSON commandRecords}'
  '';
}
