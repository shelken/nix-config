{
  config,
  lib,
}:
let
  devTools = config.shelken.dev.tools;
  devMiseTools = config.shelken.dev.miseTools;
  devWritableRoots = config.shelken.dev.sandbox.writableRoots;

  devHostCommands = config.shelken.dev.sandbox.hostCommands;

  statePaths = {
    msbHome = "${config.home.homeDirectory}/Data/sandboxes/msb";
    cacheDir = "${config.home.homeDirectory}/.cache/microsandbox";
    publishDir = "${config.home.homeDirectory}/.config/sandbox";
  };

  miseLayer = import ./_mise-layer.nix { homeDir = config.home.homeDirectory; };

  # VM 内的固定路径：guest-env.sh、launcher、sb-config.json 都从这里取
  guestPaths = rec {
    configMount = "/run/sandbox-config";
    configDir = "${configMount}/current";
    contextsDir = "/run/sandbox/contexts";
    dataDir = "/data";
  };

  # 每个声明文件在沙箱里的 (落点, 来源)：同名条目以 sandboxFiles 的内容覆盖 files 的
  sandboxOverrides = lib.foldl' (acc: tool: acc // tool.sandboxFiles) { } (
    builtins.attrValues devTools
  );
  declaredEntries = lib.concatMap (
    tool:
    lib.mapAttrsToList (target: file: {
      inherit target;
      path =
        sandboxOverrides.${target}
          or (if builtins.isAttrs file && file ? source then file.source else file);
    }) (tool.files // tool.sandboxFiles)
  ) (builtins.attrValues devTools);

  under = root: p: p == root || lib.hasPrefix "${root}/" p;
  targets = map (e: e.target) declaredEntries;

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
    guestPaths
    declaredEntries
    ;

  gitUser = config.programs.git.settings.user;

  tools = devTools;
  miseTools = devMiseTools;
  writableRoots = devWritableRoots;
  hostCommands = devHostCommands;
}
