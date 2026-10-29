{
  config,
  lib,
}:
let
  roots = config.shelken.dev.sandbox.writableRoots;
  under = root: p: p == root || lib.hasPrefix "${root}/" p;
  targets = lib.concatMap (
    tool: builtins.attrNames tool.files ++ builtins.attrNames tool.sandboxFiles
  ) (builtins.attrValues config.shelken.dev.tools);

  # 可写根与声明配置的一致性断言：
  # launcher 只执行发布清单，不兜底，所以在构建期拒绝不合法的组合。
  # .config/<X> 走 XDG（/data/xdg/config），不属于任何根。
  assertions = [
    {
      assertion = lib.all (
        r:
        r != ""
        && !(lib.hasPrefix "/" r)
        && !(lib.hasSuffix "/" r)
        && !(lib.hasPrefix ".config/" r)
        && !(builtins.elem ".." (lib.splitString "/" r))
      ) roots;
      message = "shelken.dev.sandbox.writableRoots: 每项必须是 $HOME 下的相对路径，不能为空、以 / 结尾、含 .. 或落在 .config/ 下：${builtins.toJSON roots}";
    }
    {
      assertion = lib.all (a: lib.all (b: a == b || !(under a b)) roots) roots;
      message = "shelken.dev.sandbox.writableRoots: 根之间不能嵌套：${builtins.toJSON roots}";
    }
    {
      assertion = lib.all (t: lib.hasPrefix ".config/" t || lib.any (r: under r t) roots) targets;
      message = "shelken.dev.tools.*.files 的目标必须落在某个 writableRoots 下或位于 .config/ 下，否则沙箱无处挂载：${
        builtins.toJSON (
          builtins.filter (t: !(lib.hasPrefix ".config/" t || lib.any (r: under r t) roots)) targets
        )
      }";
    }
  ];
in
{
  inherit assertions;

  paths = {
    msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
    # 宿主共用 Linux mise 目录：data 与 cache 分离，guest 侧固定挂到 /opt/sandbox-mise
    sharedMiseDir = "${config.home.homeDirectory}/Data/sandboxes/mise/aarch64-linux";
    cacheDir = "${config.home.homeDirectory}/.cache/microsandbox";
    publishDir = "${config.home.homeDirectory}/.config/sandbox";
  };

  policyFile = ./sb.yaml;
  gitUser = config.programs.git.settings.user;
  microsandboxVersion = "0.7.7";

  tools = config.shelken.dev.tools;
  miseTools = config.shelken.dev.miseTools;
  writableRoots = config.shelken.dev.sandbox.writableRoots;
  hostCommands = {
    sb = "sb 是宿主沙箱管理 CLI，沙箱内部无法嵌套管理沙箱 VM";
    just = "just hm / just sw 是宿主系统切换命令，沙箱内无法修改宿主系统配置";
  };
}
