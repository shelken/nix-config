# 声明式定时任务（hosts/<host>/tasks/<name>.nix 或模块内 shelken.tasks.<name>，加声明即生效）
#
# 任务声明形状（纯声明，不含层概念）：
#   {
#     when = "3:15";          # 日历时间，可 "3:15" 或 [ "3:15" "15:15" ]，与 every 互斥
#     # every = 7200;         # 或间隔秒数
#     # user = true;          # 默认 true：home-manager agent + task-<name> 手动命令
#     # packages = with pkgs; [ jq ]; # 运行时依赖，注入 PATH
#     # secrets = { GH_TOKEN = secretPath "github/cli-token"; }; # sops 解密文件的变量注入
#     # env = { EDITOR = "vim"; };    # 普通环境变量（明文）
#     # jitter = 600;         # launchd 调度触发时的最大随机延迟秒数，手动运行不延迟
#     # notify = { success = true; title = "Backup"; }; # 成功通知与自定义标题
#     script = '' ... '';     # bash 脚本
#   }
#
# 自动生成：launchd 定时任务（agent/daemon）+ 可执行脚本 + task-<name> 手动命令 + task 管理入口。
# 手动命令：task run <name> 或 task-<name>。
# 字段与选项契约定义在 lib/tasks.nix 的 mkTaskType，darwin 层与 home 层共用同一份。
{
  config,
  lib,
  pkgs,
  mylib,
  myvars,
  ...
}:
let
  taskCfg = config.shelken.tasks;

  tasksLib = mylib.mkTasksLib {
    inherit lib pkgs;
    homeDir = userHome;
  };

  # 用户家目录（task.nix 属 darwin 模块，但家目录由 users 模块解析，避免硬编码 /Users）
  userHome = config.users.users.${myvars.username}.home;

  taskType = tasksLib.mkTaskType;
in
{
  options.shelken.tasks = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule taskType);
    default = { };
    description = "声明式定时任务，任务文件在 hosts/<host>/tasks/ 下自动加载";
  };

  config =
    let
      rootTasks = tasksLib.rootTasks taskCfg;
    in
    {
      # 约定优于配置：hosts/<hostname>/tasks/ 自动加载，目录存在即接入，
      # host 文件无需任何接线
      shelken.tasks = mylib.loadTasks (mylib.relativeToRoot "hosts/${config.networking.hostName}/tasks") {
        inherit pkgs lib;
        secretPath = secret: config.home-manager.users.${myvars.username}.sops.secrets.${secret}.path;
      };

      assertions = lib.mapAttrsToList (name: t: {
        assertion = (t.when != [ ]) != (t.every != null);
        message = "shelken.tasks.${name}: when 与 every 必须二选一";
      }) taskCfg;

      # root 任务：launchd daemon；手动执行 sudo task-<name>
      launchd.daemons = lib.mapAttrs (name: t: {
        command = "${t.package}/bin/task-${name}";
        serviceConfig = {
          Label = "space.ooooo.task-${name}";
          RunAtLoad = false;
          KeepAlive = false;
          # 任务脚本据此区分「launchd 调度唤起」与「手动 sudo task-<name>」
          EnvironmentVariables = {
            SHELKEN_TASK_LAUNCHD = "1";
          };
          StandardOutPath = "/Library/Logs/task-${name}.log";
          StandardErrorPath = "/Library/Logs/task-${name}.log";
        }
        // (tasksLib.mkTrigger t);
      }) rootTasks;

      environment.systemPackages = lib.attrValues (lib.mapAttrs (_: t: t.package) rootTasks);
    };
}
