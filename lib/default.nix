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
  deployNode = import ./deployNode.nix;
  deployRsLib = import ./deployRsLib.nix;
  macosSystem = import ./macosSystem.nix;
  nixosSystem = import ./nixosSystem.nix;
  mkTasksLib = import ./tasks.nix;
  mkHomeManagerModule = import ./homeManagerModule.nix;
  mkHomeConfigurations = import ./homeConfigurations.nix { inherit lib myvars; };
  relativeToRoot = lib.path.append ../.;

  # 先用 yj 转成 json 再读入（构建期 IFD）
  readYaml =
    pkgs: file:
    builtins.fromJSON (
      builtins.readFile (
        pkgs.runCommand "converted.json" { } ''
          ${pkgs.yj}/bin/yj < ${file} > $out
        ''
      )
    );

  mkBoolOpt =
    default: description:
    mkOption {
      inherit default description;
      type = types.bool;
    };

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
      # 不是 Nix 系统的机器目录（OpenWrt 路由器）不参与排程，否则新增它会挪动其他主机的时段
      nonNixHostDirs = [ "router-mine" ];
      # 如果提供了hostnames，使用它；否则读取hosts目录中的目录名
      allHostnames =
        if hostnames != null then
          hostnames
        else
          builtins.attrNames (
            lib.attrsets.filterAttrs (name: type: type == "directory" && !lib.elem name nonNixHostDirs) (
              builtins.readDir ../hosts
            )
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
  # dir 下递归查找含 SKILL.md 的目录，返回 skill 名 → 目录；嵌套目录名的 / 换成 --。
  # dir 是路径字面量时值也是路径字面量（本地 skill 据此走 liveEdit），是字符串时值是字符串
  discoverSkills =
    dir:
    let
      collect =
        rel:
        let
          entries = builtins.readDir (if rel == "" then dir else dir + "/${rel}");
          child = name: if rel == "" then name else "${rel}/${name}";
        in
        if entries ? "SKILL.md" then
          [ rel ]
        else
          lib.concatMap (name: collect (child name)) (
            builtins.attrNames (lib.filterAttrs (_: type: type == "directory") entries)
          );
    in
    builtins.listToAttrs (
      map (rel: {
        name = lib.replaceStrings [ "/" ] [ "--" ] rel;
        value = dir + "/${rel}";
      }) (collect "")
    );
  # 根据 config.shelken.dotfiles.liveEdit 开关决定配置来源：
  # - liveEdit = true（本机开发环境）：使用 mkOutOfStoreSymlink 软链至本地 ~/nix-config/<相对路径>，支持免 rebuild 热加载
  # - liveEdit = false（远程部署节点/默认）：解析为仓库根下的纯 Nix store 路径，保证闭包自包含与原子回滚
  # 参数是 Nix 路径字面量（如 ./settings.toml）：文件挪动后求值即报错，而非在 liveEdit 下留下悬空软链
  mkConfigLink =
    config: path:
    let
      root = toString (relativeToRoot ".");
      abs = toString path;
      relPath = lib.removePrefix "${root}/" abs;
    in
    assert lib.assertMsg (lib.hasPrefix "${root}/" abs) "mkConfigLink: ${abs} 不在仓库内";
    assert lib.assertMsg (builtins.pathExists path) "mkConfigLink: ${relPath} 不存在";
    if config.shelken.dotfiles.liveEdit or false then
      config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/${relPath}"
    else
      "${relativeToRoot "."}/${relPath}";

  # 生成标准 Home Manager 文件配置项：{ source = mkConfigLink config path; force = true; }
  mkConfigFile = config: path: {
    source = mkConfigLink config path;
    force = true;
  };
}
