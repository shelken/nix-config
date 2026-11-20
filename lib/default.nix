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

  # 参数：
  #   hostname: 当前hostname
  #   startHour: 开始小时（包含）
  #   endHour: 结束小时（不包含）
  #   hostnames: 可选的主机名列表，用于测试（默认取机器表）
  # 返回：{ hour, minute } 对象
  calcUniformSchedule =
    {
      hostname,
      startHour,
      endHour,
      hostnames ? null,
    }:
    let
      allHostnames =
        if hostnames != null then
          hostnames
        else
          builtins.attrNames (lib.filterAttrs (_: h: h.type != "openwrt") (import ../hosts));
      hostnameHashes = map (h: {
        name = h;
        hash = builtins.hashString "sha1" h;
      }) allHostnames;
      sortedByHash = lib.sort (a: b: a.hash < b.hash) hostnameHashes;
      hostnameIndex = lib.lists.findFirstIndex (x: x == hostname) null (map (x: x.name) sortedByHash);
      totalHours = endHour - startHour;

      baseHour =
        if hostnameIndex != null then startHour + lib.mod hostnameIndex totalHours else startHour;

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

  mkSopsSecrets =
    secretsList:
    lib.listToAttrs (
      map (name: {
        inherit name;
        value = mkDefaultSecret { };
      }) secretsList
    );
  # dir 下递归查找含 SKILL.md 的目录，返回 shelken.dev.ai.skills 的条目列表；嵌套目录名的 / 换成 --。
  # dir 是路径字面量时 source 也是路径字面量（本地 skill 据此走 liveEdit），是字符串时 source 是字符串。
  # exclude、frontmatter 按 skill 名指定，写了不存在的名字时求值失败
  discoverSkills =
    dir:
    {
      exclude ? [ ],
      frontmatter ? { },
    }:
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
      found = map (rel: {
        name = lib.replaceStrings [ "/" ] [ "--" ] rel;
        source = dir + "/${rel}";
      }) (collect "");
      names = map (skill: skill.name) found;
      unknown = builtins.filter (name: !(builtins.elem name names)) (
        exclude ++ builtins.attrNames frontmatter
      );
    in
    assert lib.assertMsg (
      unknown == [ ]
    ) "discoverSkills ${toString dir}：exclude/frontmatter 里的 skill 不存在：${toString unknown}";
    map (skill: skill // { frontmatter = frontmatter.${skill.name} or { }; }) (
      builtins.filter (skill: !(builtins.elem skill.name exclude)) found
    );
  # 根据 config.shelken.dotfiles.liveEdit 开关决定配置来源：
  # - liveEdit = true（本机开发环境）：使用 mkOutOfStoreSymlink 软链至本地 ~/nix-config/<相对路径>，支持免 rebuild 热加载
  # - liveEdit = false（远程部署节点/默认）：只把该文件或目录拷进 store，保证闭包自包含与原子回滚。
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
      "${path}";

  mkConfigFile = config: path: {
    source = mkConfigLink config path;
    force = true;
  };
}
