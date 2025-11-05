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
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
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
      config ? { },
    }:
    {
      enable = true;
      config = {
        Label = "space.ooooo.${name}";
        ProgramArguments = [ ''${commandFile}'' ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/nix-hm-logs/${name}.log";
        StandardErrorPath = "/tmp/nix-hm-logs/${name}.err.log";
      }
      // config;
    };

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

}
