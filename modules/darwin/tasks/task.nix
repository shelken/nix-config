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

  # "3:15" -> { Hour = 3; Minute = 15; }
  parseTime =
    t:
    let
      parts = lib.splitString ":" t;
    in
    {
      Hour = lib.toIntBase10 (lib.elemAt parts 0);
      Minute = lib.toIntBase10 (lib.elemAt parts 1);
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
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "脚本依赖的 CLI 工具包列表，注入执行环境 PATH";
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
          runtimeInputs = config.packages;
          text = ''
            __on_exit() {
              local code=$?
              local end_time
              end_time=$(date '+%Y-%m-%d %H:%M:%S')
              echo "[$end_time] ===== Task '${name}' Finished (exit code: $code) ====="
            }
            trap __on_exit EXIT

            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== Task '${name}' Started ====="

            ${config.script}
          '';
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

      userHome = config.users.users.${myvars.username}.home;

      # 统一管理 CLI 工具: task
      taskCli = pkgs.writeShellApplication {
        name = "task";
        runtimeInputs = [
          pkgs.util-linux
          pkgs.coreutils
        ];
        text = ''
          usage() {
            echo "Usage: task <command> [args]"
            echo ""
            echo "Commands:"
            echo "  ls            列出所有定时任务及调度时间"
            echo "  run <name>    手动执行指定任务"
            echo "  log <name>    查看/跟随指定任务的日志"
            echo "  help          显示帮助"
            exit 1
          }

          cmd="''${1:-ls}"
          shift || true

          case "$cmd" in
            ls|list)
              printf "%-18s %-6s %-20s %s\n" "NAME" "TIER" "SCHEDULE" "LOG"
              printf "%-18s %-6s %-20s %s\n" "----" "----" "--------" "---"
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: t: ''
                  printf "%-18s %-6s %-20s %s\n" \
                    "${name}" \
                    "${if t.user then "user" else "root"}" \
                    "${
                      if t.every != null then "every ${toString t.every}s" else "when ${lib.concatStringsSep ", " t.when}"
                    }" \
                    "${if t.user then "~/Library/Logs/task-${name}.log" else "/Library/Logs/task-${name}.log"}"
                '') enabled
              )}
              ;;
            run)
              name="''${1:-}"
              if [ -z "$name" ]; then
                echo "Error: task name required" >&2
                echo "Usage: task run <name>" >&2
                exit 1
              fi
              case "$name" in
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: t: ''
                    ${name})
                      ${
                        if t.user then
                          "exec task-${name}"
                        else
                          ''
                            if [ "$(id -u)" -eq 0 ]; then
                              exec task-${name}
                            else
                              echo "Root 权限任务，正调用 sudo..."
                              exec sudo task-${name}
                            fi
                          ''
                      }
                      ;;
                  '') enabled
                )}
                *)
                  echo "Error: unknown task '$name'" >&2
                  exit 1
                  ;;
              esac
              ;;
            log|logs)
              name="''${1:-}"
              if [ -z "$name" ]; then
                echo "Error: task name required" >&2
                echo "Usage: task log <name>" >&2
                exit 1
              fi
              case "$name" in
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: t: ''
                    ${name})
                      log_file="${
                        if t.user then "${userHome}/Library/Logs/task-${name}.log" else "/Library/Logs/task-${name}.log"
                      }"
                      if [ ! -f "$log_file" ]; then
                        echo "Log file not found: $log_file (任务可能尚未触发运行)" >&2
                        exit 1
                      fi
                      exec tail -n 50 -f "$log_file"
                      ;;
                  '') enabled
                )}
                *)
                  echo "Error: unknown task '$name'" >&2
                  exit 1
                  ;;
              esac
              ;;
            help|--help|-h)
              usage
              ;;
            *)
              echo "Error: unknown command '$cmd'" >&2
              usage
              ;;
          esac
        '';
      };
    in
    {
      # 约定优于配置：hosts/<hostname>/tasks/ 自动加载，目录存在即接入，
      # host 文件无需任何接线
      shelken.tasks = mylib.loadTasks (mylib.relativeToRoot "hosts/${config.networking.hostName}/tasks") {
        inherit pkgs lib;
      };

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
            # 后台定时任务用 user domain，不依赖图形会话（gui domain 需登录 Aqua session）
            domain = "user";
            config = {
              RunAtLoad = false;
              KeepAlive = false;
              StandardOutPath = "${userHome}/Library/Logs/task-${name}.log";
              StandardErrorPath = "${userHome}/Library/Logs/task-${name}.log";
            }
            // (mkTrigger t);
          }
        ) userTasks;
        home.packages = lib.attrValues (lib.mapAttrs (_: t: t.package) userTasks) ++ [ taskCli ];
      };

      # root 任务：launchd daemon；手动执行 sudo task-<name>
      launchd.daemons = lib.mapAttrs (name: t: {
        command = "${t.package}/bin/task-${name}";
        serviceConfig = {
          RunAtLoad = false;
          KeepAlive = false;
          StandardOutPath = "/Library/Logs/task-${name}.log";
          StandardErrorPath = "/Library/Logs/task-${name}.log";
        }
        // (mkTrigger t);
      }) rootTasks;

      environment.systemPackages = lib.attrValues (lib.mapAttrs (_: t: t.package) rootTasks) ++ [
        taskCli
      ];
    };
}
