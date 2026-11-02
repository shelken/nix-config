# 沙箱声明规范与单一事实来源 (SandboxManifest)
# 职责：
# 1. 集中从 Home Manager config 提取沙箱所有工具、环境变量与路径规范
# 2. 集中执行 3 重静态断言检查（路径合规、不嵌套、目标覆盖）
# 3. 只做规范化与断言，不生成 derivation：配置清单与发布文件在 _config，git 配置在 _guest
# 4. 对外输出单一 manifest 对象，杜绝散装传参导致的功能丢失
{
  config,
  lib,
}:
let
  devTools = config.shelken.dev.tools;
  devMiseTools = config.shelken.dev.miseTools;
  devWritableRoots = config.shelken.dev.sandbox.writableRoots;

  # 含 default.nix 声明的 sb、just 与其他功能登记的拦截桩，由模块系统合并
  devHostCommands = config.shelken.dev.sandbox.hostCommands;

  # 规范化路径集合
  statePaths = {
    msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
    cacheDir = "${config.home.homeDirectory}/.cache/microsandbox";
    publishDir = "${config.home.homeDirectory}/.config/sandbox";
  };

  miseLayer = import ./_mise-layer.nix { homeDir = config.home.homeDirectory; };

  # 静态断言检查
  under = root: p: p == root || lib.hasPrefix "${root}/" p;
  targets = lib.concatMap (
    tool: builtins.attrNames tool.files ++ builtins.attrNames tool.sandboxFiles
  ) (builtins.attrValues devTools);

  assertions = [
    {
      assertion = lib.all (
        r:
        r != ""
        && !(lib.hasPrefix "/" r)
        && !(lib.hasSuffix "/" r)
        && !(lib.hasPrefix ".config/" r)
        && !(builtins.elem ".." (lib.splitString "/" r))
      ) devWritableRoots;
      message = "shelken.dev.sandbox.writableRoots: 每项必须是 $HOME 下的相对路径，不能为空、以 / 结尾、含 .. 或落在 .config/ 下：${builtins.toJSON devWritableRoots}";
    }
    {
      assertion = lib.all (a: lib.all (b: a == b || !(under a b)) devWritableRoots) devWritableRoots;
      message = "shelken.dev.sandbox.writableRoots: 根之间不能嵌套：${builtins.toJSON devWritableRoots}";
    }
    {
      assertion = lib.all (
        t: lib.hasPrefix ".config/" t || lib.any (r: under r t) devWritableRoots
      ) targets;
      message = "shelken.dev.tools.*.files 的目标必须落在某个 writableRoots 下或位于 .config/ 下，否则沙箱无处挂载：${
        builtins.toJSON (
          builtins.filter (
            t: !(lib.hasPrefix ".config/" t || lib.any (r: under r t) devWritableRoots)
          ) targets
        )
      }";
    }
  ];
in
{
  inherit
    assertions
    statePaths
    miseLayer
    ;

  # 规范化后的 git 身份；生成 git 配置文件是 guest 的事
  gitUser = config.programs.git.settings.user;

  tools = devTools;
  miseTools = devMiseTools;
  writableRoots = devWritableRoots;
  hostCommands = devHostCommands;
}
