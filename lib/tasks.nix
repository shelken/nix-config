# 任务系统共享核心：darwin 层（root daemon）与 home 层（user agent + task CLI）共用。
# 两入口（just sw 内嵌 / just hm 独立）各自评估任务声明，生成逻辑必须单源，
# 否则同一份声明在两个入口行为漂移。
{
  lib,
  pkgs,
  homeDir,
}:
rec {
  # 任务字段唯一默认值源：darwin 与 home 两端共用的 mkTaskType submodule
  # 都从这里取默认值，新增字段只改这一处，杜绝两处默认漂移
  taskDefaults = {
    user = true;
    when = [ ];
    every = null;
    packages = [ ];
    secrets = { };
    env = { };
    jitter = null;
    notify = {
      failure = true;
      success = false;
      title = null;
    };
    island = false;
  };

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

  # when/every -> launchd 触发键
  mkTrigger =
    t:
    if t.every != null then
      { StartInterval = t.every; }
    else
      { StartCalendarInterval = map parseTime t.when; };

  # 动态任务管理 CLI 工具: task（运行时读取 launchd plist，不写死任务列表）
  mkTaskCli = pkgs.writeShellApplication {
    name = "task";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
    ];
    text = ''
      python3 - "$@" <<'EOF'
      import glob
      import os
      import plistlib
      import shutil
      import sys

      USER_HOME = ${builtins.toJSON homeDir}
      TASK_PREFIX = "space.ooooo.task-"
      TASK_DIRS = (
          ("user", os.path.join(USER_HOME, "Library/LaunchAgents")),
          ("root", "/Library/LaunchDaemons"),
      )

      def get_tasks():
          tasks = {}
          for tier, directory in TASK_DIRS:
              pattern = os.path.join(directory, f"{TASK_PREFIX}*.plist")
              for path in glob.glob(pattern):
                  with open(path, "rb") as f:
                      data = plistlib.load(f)

                  label = data.get("Label", "")
                  if not label.startswith(TASK_PREFIX):
                      continue
                  name = label[len(TASK_PREFIX):]

                  schedule = "manual"
                  if "StartInterval" in data:
                      schedule = f"every {data['StartInterval']}s"
                  elif "StartCalendarInterval" in data:
                      intervals = data["StartCalendarInterval"]
                      if isinstance(intervals, dict):
                          intervals = [intervals]
                      times = [
                          f"{item.get('Hour', 0):02d}:{item.get('Minute', 0):02d}"
                          for item in intervals
                      ]
                      schedule = f"when {', '.join(times)}"

                  log_path = data.get("StandardOutPath", "")
                  if not log_path:
                      if tier == "user":
                          log_path = os.path.join(USER_HOME, f"Library/Logs/task-{name}.log")
                      else:
                          log_path = f"/Library/Logs/task-{name}.log"

                  tasks[name] = {
                      "tier": tier,
                      "schedule": schedule,
                      "log": log_path,
                  }
          return tasks

      def usage(exit_code=0):
          print("Usage: task <command> [args]\n")
          print("Commands:")
          print("  ls, list      列出所有定时任务及调度时间（动态实时）")
          print("  run <name>    手动执行指定任务")
          print("  log <name>    查看/跟随指定任务的日志")
          print("  help          显示帮助")
          sys.exit(exit_code)

      def cmd_ls(tasks):
          print(f"{'NAME':<18} {'TIER':<6} {'SCHEDULE':<24} {'LOG'}")
          print(f"{'----':<18} {'----':<6} {'--------':<24} {'---'}")
          for name in sorted(tasks):
              task = tasks[name]
              print(f"{name:<18} {task['tier']:<6} {task['schedule']:<24} {task['log']}")

      def cmd_run(tasks, name, extra_args):
          if not name:
              print("Error: task name required\nUsage: task run <name>", file=sys.stderr)
              sys.exit(1)

          command = f"task-{name}"
          task = tasks.get(name)
          if not shutil.which(command) and not task:
              print(f"Error: unknown task '{name}'", file=sys.stderr)
              sys.exit(1)

          tier = task["tier"] if task else "user"
          if tier == "root" and os.geteuid() != 0:
              print("Root 权限任务，正调用 sudo...", file=sys.stderr)
              os.execvp("sudo", ["sudo", command] + extra_args)
          os.execvp(command, [command] + extra_args)

      def cmd_log(tasks, name):
          if not name:
              print("Error: task name required\nUsage: task log <name>", file=sys.stderr)
              sys.exit(1)

          task = tasks.get(name)
          candidates = [
              os.path.join(USER_HOME, f"Library/Logs/task-{name}.log"),
              f"/Library/Logs/task-{name}.log",
          ]
          if task:
              candidates.insert(0, task["log"])

          log_file = next((path for path in candidates if os.path.isfile(path)), None)
          if not log_file:
              print(f"Log file not found for task '{name}' (任务可能尚未触发运行)", file=sys.stderr)
              sys.exit(1)
          os.execvp("tail", ["tail", "-n", "50", "-f", log_file])

      def main():
          args = sys.argv[1:]
          command = args[0] if args else "ls"
          sub_args = args[1:]
          tasks = get_tasks()

          if command in ("ls", "list"):
              cmd_ls(tasks)
          elif command == "run":
              cmd_run(tasks, sub_args[0] if sub_args else "", sub_args[1:])
          elif command in ("log", "logs"):
              cmd_log(tasks, sub_args[0] if sub_args else "")
          elif command in ("help", "--help", "-h"):
              usage(0)
          elif command in tasks:
              cmd_run(tasks, command, sub_args)
          else:
              print(f"Error: unknown command '{command}'\n", file=sys.stderr)
              usage(1)

      if __name__ == "__main__":
          main()
      EOF
    '';
  };

  # 任务灵动岛：gui 域观察者，显示由任务双写出来的实时日志
  taskIsland = pkgs.writeShellApplication {
    name = "task-island";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/task-island"
      SRC="${../modules/features/darwin/tasks/task-island.swift}"
      # 用源码内容哈希做缓存键：nix store 里的文件 mtime 恒为 epoch，-nt 判据永远不成立
      HASH="$(sha256sum "$SRC" | cut -c1-16)"
      BIN="$CACHE_DIR/task-island-$HASH"

      if [ ! -x "$BIN" ]; then
        mkdir -p "$CACHE_DIR"
        rm -f "$CACHE_DIR"/task-island-*
        # 编译失败只意味着这次没有灵动岛可看，任务执行不受任何影响
        if ! swiftc -O -parse-as-library "$SRC" -o "$BIN"; then
          echo "task-island: swiftc 编译失败，跳过灵动岛显示" >&2
          exit 0
        fi
      fi

      exec "$BIN" "$@"
    '';
  };

  # 任务包装脚本：起止记录 + 抖动 + 通知。t 来自 mkTaskType submodule，字段已带默认值
  mkPackage =
    name: t:
    let
      secretExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: secretPath: ''
          if [ ! -r "${secretPath}" ]; then
            echo "Task '${name}': required secret ${var} is not readable: ${secretPath}" >&2
            exit 1
          fi
          ${var}="$(<"${secretPath}")"
          export ${var}
        '') t.secrets
      );

      # 把任意文本原样塞进双引号 bash 串：转义反斜杠、双引号、$ 与反引号。
      # 不用单引号包裹是为了避开 shellcheck 的 SC2016（连 info 级都会让构建失败）
      quoteDouble = s: builtins.replaceStrings [ "\\" "\"" "$" "`" ] [ "\\\\" "\\\"" "\\$" "\\`" ] s;

      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: value: ''export ${var}="${quoteDouble value}"'') t.env
      );

      # 抖动只在 launchd 调度唤起时生效；手动 task run 调试无延迟，CANCEL_JITTER=true 强制跳过。
      # 放在包装脚本里、灵动岛标记之前：休眠期间任务还没开始，不应占着灵动岛
      jitterBlock = lib.optionalString (t.jitter != null && t.jitter > 0) ''
        if [ "''${SHELKEN_TASK_LAUNCHD:-}" = "1" ] && [ "''${CANCEL_JITTER:-}" != "true" ]; then
          jitter=$(( RANDOM % ${toString t.jitter} ))
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jitter delay: ''${jitter}s（跳过请设 CANCEL_JITTER=true）"
          sleep "$jitter"
        fi
      '';

      runnerBin = pkgs.writeShellScript "task-${name}-runner" ''
        ${secretExports}
        ${envExports}
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== Task '${name}' Started ====="
        ${t.script}
      '';

      canonicalLog =
        if t.user then "${homeDir}/Library/Logs/task-${name}.log" else "/Library/Logs/task-${name}.log";

      islandDir = "${homeDir}/Library/Logs/task-island";

      # 通知：默认仅 launchd 调度唤起且非零退出时提示失败，可配置成功也通知与自定义标题。
      # 标题来自配置，必须转义后再拼进脚本；消息是模板自己拼的，含运行期展开的变量
      mkNotify =
        {
          fallbackTitle,
          message,
          sound,
        }:
        ''
          ${pkgs.terminal-notifier}/bin/terminal-notifier \
            -title "${quoteDouble (if t.notify.title != null then t.notify.title else fallbackTitle)}" \
            -message "${message}" \
            -sound ${sound} \
            -group "task-${name}" \
            -open "file://${canonicalLog}" \
            2>/dev/null || true
        '';

      # 两个开关都关时整段不发，否则会留下空的 if/then/fi 让 bash 报语法错误
      notifyOnExit =
        if !t.user || !(t.notify.failure || t.notify.success) then
          "" # root daemon 通常无图形会话；开关全关则不需要通知
        else
          ''
            # 仅 launchd 调度触发时通知，手动 task run 调试保持静默
            if [ "''${SHELKEN_TASK_LAUNCHD:-}" = "1" ]; then
              ${lib.optionalString t.notify.failure ''
                if [ "$code" -ne 0 ]; then
                  ${mkNotify {
                    fallbackTitle = "Task Failed: ${name}";
                    message = "退出码 \${code}, 点击查看日志";
                    sound = "Basso";
                  }}
                fi
              ''}
              ${lib.optionalString t.notify.success ''
                if [ "$code" -eq 0 ]; then
                  ${mkNotify {
                    fallbackTitle = "Task Completed: ${name}";
                    message = "执行成功, 点击查看日志";
                    sound = "Glass";
                  }}
                fi
              ''}
            fi
          '';

      executionBody =
        if t.island then
          ''
            # 灵动岛是旁观者：下面两件事都不影响任务执行、输出与退出码。
            # 双写一份到灵动岛日志（不含 launchd 自身的重定向，避免重复），并由 gui 域的
            # task-island agent 跟随；标记文件触发 launchd WatchPaths，没有图形会话时不触发。
            mkdir -p "${islandDir}"
            : > "${islandDir}/${name}.log"
            exec > >(tee -a "${islandDir}/${name}.log") 2>&1
            # 先删再建：WatchPaths 只在目录条目变化时触发，单纯覆盖已有文件不会触发
            rm -f "${islandDir}/${name}.marker" "${islandDir}/${name}.exit"
            printf '%s\n%s\n' "$$" "${canonicalLog}" > "${islandDir}/${name}.marker"

            "${runnerBin}"
          ''
        else
          ''
            "${runnerBin}"
          '';
    in
    pkgs.writeShellApplication {
      name = "task-${name}";
      runtimeInputs = t.packages;
      text = ''
        __on_exit() {
          local code=$?
          local end_time
          end_time=$(date '+%Y-%m-%d %H:%M:%S')
          echo "[$end_time] ===== Task '${name}' Finished (exit code: $code) ====="
          # 确定性退出码通道：tee 异步落盘有滞后且 bash 退出后 WatchPaths 观察者
          # 可能先看到进程死亡，写副档让灵动岛免竞态读取真实退出码
          if [ -d "${islandDir}" ] && [ -e "${islandDir}/${name}.marker" ]; then
            printf '%s' "$code" > "${islandDir}/${name}.exit"
          fi
          ${notifyOnExit}
        }
        trap __on_exit EXIT

        ${jitterBlock}
        ${executionBody}
      '';
    };

  # 任务声明 submodule：darwin 层（root daemon）与 home 层（user agent）共用同一份
  # 选项契约，两端只能有一个定义源；默认值全部来自 taskDefaults
  mkTaskType =
    { name, config, ... }:
    {
      options = {
        when = lib.mkOption {
          type = lib.types.coercedTo lib.types.str (t: [ t ]) (lib.types.listOf lib.types.str);
          default = taskDefaults.when;
          description = "日历时间 HH:MM（launchd StartCalendarInterval，睡眠错过唤醒后补跑）";
          example = "3:15";
        };
        every = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = taskDefaults.every;
          description = "间隔秒数（launchd StartInterval），与 when 互斥";
          example = 7200;
        };
        user = lib.mkOption {
          type = lib.types.bool;
          default = taskDefaults.user;
          description = "true: 用户态 home-manager agent；false: root launchd daemon";
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = taskDefaults.packages;
          description = "脚本依赖的 CLI 工具包列表，注入执行环境 PATH";
        };
        secrets = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = taskDefaults.secrets;
          description = "任务需要的环境变量到 sops 解密文件路径的映射，运行时读文件注入变量";
          example = lib.literalExpression ''
            { GH_TOKEN = secretPath "github/cli-token"; }
          '';
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = taskDefaults.env;
          description = "任务运行时注入的普通环境变量（明文，勿放密钥）";
          example = {
            EDITOR = "vim";
          };
        };
        jitter = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = taskDefaults.jitter;
          description = "launchd 调度触发时的最大随机延迟秒数，手动运行不延迟";
          example = 600;
        };
        notify = lib.mkOption {
          type = lib.types.submodule {
            options = {
              failure = lib.mkOption {
                type = lib.types.bool;
                default = taskDefaults.notify.failure;
                description = "任务失败时发系统通知";
              };
              success = lib.mkOption {
                type = lib.types.bool;
                default = taskDefaults.notify.success;
                description = "任务成功时发系统通知";
              };
              title = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = taskDefaults.notify.title;
                description = "通知标题，null 使用默认标题";
              };
            };
          };
          default = taskDefaults.notify;
          description = "系统通知行为（仅用户态任务与图形会话）";
        };
        script = lib.mkOption {
          type = lib.types.lines;
          description = "bash 脚本内容";
        };
        island = lib.mkOption {
          type = lib.types.bool;
          default = taskDefaults.island;
          description = "是否在执行时通过灵动岛展示任务状态；root 任务需图形会话在席才有人观看";
        };
        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "生成的可执行脚本（内部用）";
        };
      };
      config = {
        package = mkPackage name {
          inherit (config)
            user
            packages
            secrets
            env
            jitter
            notify
            script
            island
            ;
        };
      };
    };

  # 启用过滤（有调度才生成，无 when/every 的任务声明视为未启用）
  enabled = lib.filterAttrs (_: t: t.when != [ ] || t.every != null);

  # user 任务（home 层 agent）
  userTasks = tasks: lib.filterAttrs (_: t: t.user) (enabled tasks);

  # root 任务（darwin 层 daemon）
  rootTasks = tasks: lib.filterAttrs (_: t: !t.user) (enabled tasks);
}
