# 声明式定时任务（hosts/<host>/tasks/<name>.nix，加文件即生效）
#
# 任务文件形状（纯声明，不含层概念）：
#   {
#     when = "3:15";          # 日历时间，可 "3:15" 或 [ "3:15" "15:15" ]，与 every 互斥
#     # every = 7200;         # 或间隔秒数
#     # user = true;          # 默认 true：home-manager agent + task-<name> 手动命令
#     script = '' ... '';     # bash 脚本
#   }
#
# 自动生成：launchd 定时任务（agent/daemon）+ 可执行脚本 + task-<name> 手动命令。
# 手动命令：user 层 task-<name>；root 层 sudo task-<name>。
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

  # "3:15" -> { Hour = 3; Minute = 15; }
  parseTime =
    t:
    let
      parts = lib.splitString ":" t;
    in
    {
      Hour = lib.toInt (lib.elemAt parts 0);
      Minute = lib.toInt (lib.elemAt parts 1);
    };

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
        package = pkgs.writeShellApplication {
          name = "task-${name}";
          text = config.script;
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
      enabled = lib.filterAttrs (_: t: t.when != [ ] || t.every != null) taskCfg;
      mkTrigger =
        t:
        if t.every != null then
          { StartInterval = t.every; }
        else
          { StartCalendarInterval = map parseTime t.when; };
      userTasks = lib.filterAttrs (_: t: t.user) enabled;
      rootTasks = lib.filterAttrs (_: t: !t.user) enabled;
    in
    {
      assertions = lib.mapAttrsToList (name: t: {
        assertion = (t.when != [ ]) != (t.every != null);
        message = "shelken.tasks.${name}: when 与 every 必须二选一";
      }) taskCfg;

      # 用户任务：HM launchd agent + task-<name> 手动命令
      home-manager.users.${myvars.username} = {
        launchd.agents = lib.mapAttrs (
          name: t:
          mylib.mkLaunchCommand {
            inherit name;
            commandFile = "${t.package}/bin/task-${name}";
            config = {
              RunAtLoad = false;
              KeepAlive = false;
            }
            // (mkTrigger t);
          }
        ) userTasks;
        home.packages = lib.attrValues (lib.mapAttrs (_: t: t.package) userTasks);
      };

      # root 任务：launchd daemon；手动执行 sudo task-<name>
      launchd.daemons = lib.mapAttrs (name: t: {
        command = "${t.package}/bin/task-${name}";
        serviceConfig = {
          RunAtLoad = false;
          KeepAlive = false;
        }
        // (mkTrigger t);
      }) rootTasks;

      environment.systemPackages = lib.attrValues (lib.mapAttrs (_: t: t.package) rootTasks);
    };
}
