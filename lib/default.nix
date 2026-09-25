{
  lib,
  secrets,
  myvars,
  ...
}:
let
  inherit (lib) mkOption types;
in
rec {
  colmenaSystem = import ./colmenaSystem.nix;
  deployNode = import ./deployNode.nix;
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
  mkTasksLib = import ./tasks.nix;
  relativeToRoot = lib.path.append ../.;
  # 扫入当前目录所有除default.nix的以nix结尾的文件，以及第一层目录
  # 返回一个目录list
  scanPaths =
    path:
    builtins.map (f: (path + "/${f}")) (
      builtins.attrNames (
        lib.attrsets.filterAttrs (
          path: _type:
          (_type == "directory") # include directories
          || (
            (path != "default.nix") # ignore default.nix
            && (lib.strings.hasSuffix ".nix" path) # include .nix files
          )
        ) (builtins.readDir path)
      )
    );

  mkBoolOpt =
    default: description:
    mkOption {
      inherit default description;
      type = types.bool;
    };

  mkLoginItemString =
    { app_name }:
    let
      appPath = "/Applications/${app_name}.app";
      hiddenAppleScript = "false"; # 默认设置为不隐藏
    in
    ''
      echo >&2 'Add LoginItem for ${app_name}'
      /usr/bin/osascript -e 'tell application "System Events" to make login item at end with properties {path:"${appPath}", hidden:${hiddenAppleScript}}'
    '';

  mkLaunchCommand =
    {
      name,
      commandFile,
      domain ? "user",
      config ? { },
    }:
    {
      enable = true;
      inherit domain;
      config = {
        Label = "space.ooooo.${name}";
        ProgramArguments = [ "${commandFile}" ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/nix-hm-logs/${name}.log";
        StandardErrorPath = "/tmp/nix-hm-logs/${name}.err.log";
      }
      // config;
    };

  # 加载目录下所有 .nix 任务声明文件为 { <name> = 声明; } 映射
  # 任务文件支持裸 attrset 或函数 { pkgs, ... }: 声明，配合 shelken.tasks 的 attrsOf submodule 使用
  # 目录不存在时返回空，调用方无需守卫
  loadTasks =
    path: args:
    if !builtins.pathExists path then
      { }
    else
      builtins.listToAttrs (
        map
          (
            f:
            let
              raw = import (path + "/${f}");
              val = if builtins.isFunction raw then raw args else raw;
            in
            {
              name = lib.strings.removeSuffix ".nix" f;
              value = val;
            }
          )
          (
            lib.filter (f: f != "default.nix" && lib.strings.hasSuffix ".nix" f) (
              builtins.attrNames (builtins.readDir path)
            )
          )
      );

  # 计算hostname在指定时间段内的均匀分布时间
  # 将读取hosts目录下所有一级目录名来排序定位
  # 分钟数使用 hostname 长度
  # 参数：
  #   hostname: 当前hostname
  #   startHour: 开始小时（包含）
  #   endHour: 结束小时（不包含）
  #   hostnames: 可选的主机名列表，用于测试（默认读取hosts目录）
  # 返回：{ hour, minute } 对象
  calcUniformSchedule =
    {
      hostname,
      startHour,
      endHour,
      hostnames ? null,
    }:
    let
      # 如果提供了hostnames，使用它；否则读取hosts目录中的目录名
      allHostnames =
        if hostnames != null then
          hostnames
        else
          builtins.attrNames (
            lib.attrsets.filterAttrs (_name: type: type == "directory") (builtins.readDir ../hosts)
          );
      # 按hash值排序获得稳定分布
      hostnameHashes = map (h: {
        name = h;
        hash = builtins.hashString "sha1" h;
      }) allHostnames;
      sortedByHash = lib.sort (a: b: a.hash < b.hash) hostnameHashes;
      hostnameIndex = lib.lists.findFirstIndex (x: x == hostname) null (map (x: x.name) sortedByHash);
      totalHours = endHour - startHour;

      # 在指定时间段内均匀分布
      baseHour =
        if hostnameIndex != null then startHour + lib.mod hostnameIndex totalHours else startHour; # 默认开始小时

      # 使用 hostname 长度作为基础分钟数
      baseMinute = lib.mod (builtins.stringLength hostname * 13) 60;
    in
    {
      hour = baseHour;
      minute = baseMinute;
    };

  mkDefaultSecret =
    overrides@{ ... }:
    {
      sopsFile = secrets + "/sops/secrets/${myvars.username}/default.yaml";
      mode = "0500";
    }
    // overrides;

  # 创建的密钥仅自己可读取（500）
  mkSopsSecrets =
    secretsList:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = mkDefaultSecret { };
      }) secretsList
    );
  # 解析 "alt-f"、"alt-shift-enter" 等人类可读快捷键为 macOS Carbon 规范 JSON 字符串
  # 用于 Tinycast 等基于 Carbon 键码与修饰键掩码的应用热键配置
  darwinKeyCombo =
    str:
    let
      keyMap = {
        a = 0;
        s = 1;
        d = 2;
        f = 3;
        h = 4;
        g = 5;
        z = 6;
        x = 7;
        c = 8;
        v = 9;
        b = 11;
        q = 12;
        w = 13;
        e = 14;
        r = 15;
        y = 16;
        t = 17;
        "1" = 18;
        "2" = 19;
        "3" = 20;
        "4" = 21;
        "6" = 22;
        "5" = 23;
        "=" = 24;
        "9" = 25;
        "7" = 26;
        "-" = 27;
        "8" = 28;
        "0" = 29;
        "]" = 30;
        o = 31;
        u = 32;
        "[" = 33;
        i = 34;
        p = 35;
        l = 37;
        j = 38;
        "'" = 39;
        k = 40;
        ";" = 41;
        "\\" = 42;
        "," = 43;
        "/" = 44;
        n = 45;
        m = 46;
        "." = 47;
        "`" = 50;
        return = 36;
        enter = 36;
        tab = 48;
        space = 49;
        delete = 51;
        backspace = 51;
        escape = 53;
        esc = 53;
        left = 123;
        right = 124;
        down = 125;
        up = 126;
        f1 = 122;
        f2 = 120;
        f3 = 99;
        f4 = 118;
        f5 = 96;
        f6 = 97;
        f7 = 98;
        f8 = 100;
        f9 = 101;
        f10 = 109;
        f11 = 103;
        f12 = 111;
      };
      modMap = {
        cmd = 256;
        command = 256;
        shift = 512;
        alt = 2048;
        opt = 2048;
        option = 2048;
        ctrl = 4096;
        control = 4096;
      };
      normalized = builtins.replaceStrings [ "+" " " ] [ "-" "" ] (lib.toLower str);
      tokens = builtins.filter (x: builtins.isString x && x != "") (builtins.split "-" normalized);
      len = builtins.length tokens;
      key = builtins.elemAt tokens (len - 1);
      mods = builtins.genList (i: builtins.elemAt tokens i) (len - 1);
      keyCode = keyMap.${key} or (throw "darwinKeyCombo: 未知按键名 '${key}' (位于快捷键 '${str}')");
      modifiers = builtins.foldl' (
        acc: m: acc + (modMap.${m} or (throw "darwinKeyCombo: 未知修饰键 '${m}' (位于快捷键 '${str}')"))
      ) 0 mods;
    in
    builtins.toJSON {
      combo._0 = {
        carbonKeyCode = keyCode;
        carbonModifiers = modifiers;
      };
    };
}
