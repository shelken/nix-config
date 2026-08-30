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
in
{
  launchd.agents = lib.mapAttrs (
    name: t:
    mylib.mkLaunchCommand {
      name = "task-${name}";
      commandFile = "${tasksLib.mkPackage name t}/bin/task-${name}";
      # 后台定时任务用 user domain，不依赖图形会话（gui domain 需登录 Aqua session）
      domain = "user";
      config = {
        RunAtLoad = false;
        KeepAlive = false;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/task-${name}.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/task-${name}.log";
      }
      // (tasksLib.mkTrigger t);
    }
  ) userTasks;

  home.packages = (lib.mapAttrsToList tasksLib.mkPackage userTasks) ++ [ taskCli ];
}
