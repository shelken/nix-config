# hosts/<host>/tasks/ 中的 user 任务：home-manager LaunchAgent + task-<name> 手动命令。
#
# 为什么在 home 层：两个 HM 入口（just sw 内嵌 / just hm 独立）共同持有
# 用户态 agent，任一入口切换都不会清理另一入口部署的 agent
# （否则独立 just hm 会把 sw 生成的 profile-usage agent 删掉）。
{
  config,
  lib,
  pkgs,
  mylib,
  hostname,
  ...
}:
let
  tasksLib = mylib.mkTasksLib {
    inherit lib pkgs;
    homeDir = config.home.homeDirectory;
  };

  taskCfg = mylib.loadTasks (mylib.relativeToRoot "hosts/${hostname}/tasks") {
    inherit pkgs lib;
    secretPath = secret: config.sops.secrets.${secret}.path;
  };

  tasks = lib.mapAttrs (name: t: tasksLib.withDefaults (tasksLib.checkTask name t)) taskCfg;
  userTasks = tasksLib.userTasks tasks;

  taskCli = tasksLib.mkTaskCli;

  islandDir = "${config.home.homeDirectory}/Library/Logs/task-island";
  islandEnabled = lib.any (t: t.island) (lib.attrValues userTasks);

  # 灵动岛进程：必须放 gui 域（只有 Aqua session 的进程能连 WindowServer），
  # 由任务触碰 marker 经 launchd WatchPaths 按需拉起。没有图形登录会话时该 agent
  # 根本不存在，任务本身在 user 域照常执行，二者互不影响。
  islandAgents = lib.optionalAttrs islandEnabled {
    task-island = mylib.mkLaunchCommand {
      name = "task-island";
      domain = "gui";
      commandFile = "${tasksLib.taskIsland}/bin/task-island";
      config = {
        RunAtLoad = false;
        KeepAlive = false;
        WatchPaths = [ islandDir ];
        ProgramArguments = [
          "${tasksLib.taskIsland}/bin/task-island"
          "watch"
          "--dir"
          islandDir
        ];
      };
    };
  };
in
{
  launchd.agents =
    lib.mapAttrs (
      name: t:
      mylib.mkLaunchCommand {
        name = "task-${name}";
        commandFile = "${tasksLib.mkPackage name t}/bin/task-${name}";
        # 始终 user domain：任务执行不与图形会话绑定（gui domain 在无图形登录时不运行）
        domain = "user";
        config = {
          RunAtLoad = false;
          KeepAlive = false;
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/task-${name}.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/task-${name}.log";
        }
        // (tasksLib.mkTrigger t);
      }
    ) userTasks
    // islandAgents;

  # WatchPaths 需要目录预先存在
  home.file."Library/Logs/task-island/.keep".text = "";

  home.packages = (lib.mapAttrsToList tasksLib.mkPackage userTasks) ++ [
    taskCli
    tasksLib.taskIsland
  ];
}
