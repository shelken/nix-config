# 沙箱声明规范与单一事实来源 (SandboxManifest)
# 职责：
# 1. 集中从 Home Manager config 提取沙箱所有工具、环境变量与路径规范
# 2. 集中执行 3 重静态断言检查（路径合规、不嵌套、目标覆盖）
# 3. 统一生成只读 mise 配置、文件清单 (configManifest, declaredPaths, writableRootsFile)
# 4. 对外输出单一 manifest 对象，杜绝散装传参导致的功能丢失
{
  config,
  lib,
  pkgs,
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
    sharedMiseDir = "${config.home.homeDirectory}/Data/sandboxes/mise/aarch64-linux";
    publishDir = "${config.home.homeDirectory}/.config/sandbox";
  };

  # Git 全局配置（用于克隆和私有依赖凭据改写）
  gitConfig = (pkgs.formats.gitIni { }).generate "sandbox-git-config" {
    user = config.programs.git.settings.user;
    credential."https://github.com".helper = "!gh auth git-credential";
    url."https://github.com/".insteadOf = "git@github.com:";
  };

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

  # guest 只读层 mise 配置
  readOnlyMiseToml = (pkgs.formats.toml { }).generate "sandbox-mise.toml" {
    tools = devMiseTools;
  };

  # 收集工具声明文件与沙箱覆盖项
  toolTargets =
    tool:
    lib.mapAttrsToList (target: file: { inherit target file; }) tool.files
    ++ lib.mapAttrsToList (target: file: { inherit target file; }) (
      removeAttrs tool.sandboxFiles (builtins.attrNames tool.files)
    );
  allToolFiles = lib.concatMap toolTargets (builtins.attrValues devTools);

  sandboxOverrides = lib.foldl' (acc: tool: acc // tool.sandboxFiles) { } (
    builtins.attrValues devTools
  );
  resolveEntry =
    item:
    if sandboxOverrides ? ${item.target} then
      sandboxOverrides.${item.target}
    else if builtins.isAttrs item.file && item.file ? source then
      item.file.source
    else
      item.file;

  configEntries = map (item: {
    inherit (item) target;
    path = resolveEntry item;
  }) allToolFiles;

  configManifest = pkgs.writeText "sandbox-config-manifest" (
    lib.concatStringsSep "\n" (map (e: "${e.target}\t${toString e.path}") configEntries) + "\n"
  );

  declaredPaths = pkgs.writeText "declared-paths" (
    lib.concatStringsSep "\n" (map (e: e.target) configEntries) + "\n"
  );

  writableRootsFile = pkgs.writeText "writable-roots" (
    lib.concatMapStrings (r: "${r}\n") (lib.unique (lib.sort lib.lessThan devWritableRoots))
  );
in
{
  inherit
    assertions
    gitConfig
    statePaths
    readOnlyMiseToml
    configManifest
    declaredPaths
    writableRootsFile
    ;

  tools = devTools;
  miseTools = devMiseTools;
  writableRoots = devWritableRoots;
  hostCommands = devHostCommands;
}
