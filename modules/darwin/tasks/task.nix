# 声明式定时任务（hosts/<host>/tasks/<name>.nix，加文件即生效）
#
# 任务文件形状（纯声明，不含层概念）：
#   {
#     when = "3:15";          # 日历时间，可 "3:15" 或 [ "3:15" "15:15" ]，与 every 互斥
#     # every = 7200;         # 或间隔秒数
#     # user = true;          # 默认 true：home-manager agent + task-<name> 手动命令
#     # packages = with pkgs; [ jq ]; # 运行时依赖，注入 PATH
#     script = '' ... '';     # bash 脚本
#   }
#
# 自动生成：launchd 定时任务（agent/daemon）+ 可执行脚本 + task-<name> 手动命令 + task 管理入口。
# 手动命令：task run <name> 或 task-<name>。
# 复杂服务（需要 secrets/policy/CLI 工具，如 kopia）不属此模型，走常规 module。
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

  taskType =
    { config, name, ... }:
    {
      options = {
        when = lib.mkOption {
          type = lib.types.coercedTo lib.types.str (t: [ t ]) (lib.types.listOf lib.types.str);
          default = [ ];
          description = "日历时间 HH:MM（launchd StartCalendarInterval，睡眠错过唤醒后补跑）";
          example = "3:15";
        };
        every = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "间隔秒数（launchd StartInterval），与 when 互斥";
          example = 7200;
        };
        user = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "true: 用户态 home-manager agent；false: root launchd daemon";
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "脚本依赖的 CLI 工具包列表，注入执行环境 PATH";
        };
        secrets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "任务需要的环境变量到 sops 解密文件路径的映射，自动在运行时注入环境变量";
          example = lib.literalExpression ''
            { GH_TOKEN = secretPath "github/cli-token"; }
          '';
        };
        script = lib.mkOption {
          type = lib.types.lines;
          description = "bash 脚本内容";
        };
        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "生成的可执行脚本（内部用）";
        };
      };
      config = {
        package = tasksLib.mkPackage name {
          inherit (config)
            user
            packages
            secrets
            script
            ;
        };
      };
    };
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
          StandardOutPath = "/Library/Logs/task-${name}.log";
          StandardErrorPath = "/Library/Logs/task-${name}.log";
        }
        // (tasksLib.mkTrigger t);
      }) rootTasks;

      environment.systemPackages = lib.attrValues (lib.mapAttrs (_: t: t.package) rootTasks);
    };
}
