{
  config,
  lib,
  pkgs,
  mylib,
  ...
}:
let
  scriptsDir = ./scripts;

  scriptFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".sh" name) (
    builtins.readDir scriptsDir
  );

  scripts = lib.mapAttrs' (
    fileName: _:
    let
      name = lib.removeSuffix ".sh" fileName;
    in
    lib.nameValuePair name (
      pkgs.writeShellScriptBin name (builtins.readFile (scriptsDir + "/${fileName}"))
    )
  ) scriptFiles;

  # 显示器输入源：17/18/15 是 GE278UR 的 DDC inputSelect 源码值，CLI 别名与启动器条目共用这张表
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
    {
      name = "复制前台应用 Bundle ID";
      command = lib.getExe scripts.get-app-bundleid;
      iconSymbol = "doc.on.clipboard";
    }
    {
      name = "在 Finder 当前目录打开 Kitty";
      command = lib.getExe scripts.open-terminal-in-finder-path;
      iconSymbol = "folder";
    }
  ]
  ++ displayCommands;

  # App 以命令 id 索引别名、收藏与快捷键，所以 id 必须由名字稳定派生
  commandID =
    name:
    let
      h = builtins.hashString "sha256" name;
    in
    "${builtins.substring 0 8 h}-${builtins.substring 8 4 h}-${builtins.substring 12 4 h}-${builtins.substring 16 4 h}-${builtins.substring 20 12 h}";

  hotkeyedCommands = builtins.filter (cmd: cmd ? hotkey) customCommands;

  commandRecords = map (cmd: {
    id = commandID cmd.name;
    inherit (cmd) name command iconSymbol;
  }) customCommands;

  # 命令内容与它的快捷键都不进 settings.json，App 只能从 UserDefaults 读到，所以这两项留在这里。
  # App 快捷键、启动器可见性等偏好一律写在 settings.json：镜像打开后 App 以文件为准，
  # 在这里重复声明只会被文件清掉。
  tinycastDefaults = {
    boundCustomCommandIDs = map (cmd: commandID cmd.name) hotkeyedCommands;
    settingsFileEnabled = true;
  }
  // builtins.listToAttrs (
    map (cmd: {
      name = "hotkey.customCommand.${commandID cmd.name}";
      value = mylib.darwinKeyCombo cmd.hotkey;
    }) hotkeyedCommands
  );
in
{
  home.packages = builtins.attrValues scripts ++ displayPackages;

  targets.darwin.defaults."com.tinycast.app" = tinycastDefaults;

  xdg.configFile."tinycast/scripts" = mylib.mkConfigFile config scriptsDir;

  # settings.json 由 App 回写，所以源文件必须可写：liveEdit 主机软链到仓库，其他主机链到只读
  # 的 Store 路径，启动时照常应用，但 App 内改动保存会失败
  xdg.configFile."tinycast/settings.json" = mylib.mkConfigFile config ./settings.json;

  # 排在 setDarwinDefaults 之后，避免两个步骤的写入顺序不明确
  home.activation.tinycastCustomCommands = lib.hm.dag.entryAfter [ "setDarwinDefaults" ] ''
    /usr/bin/swift ${./sync-commands.swift} '${builtins.toJSON commandRecords}'
  '';
}
