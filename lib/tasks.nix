# 任务系统共享核心：darwin 层（root daemon）与 home 层（user agent + task CLI）共用。
# 两入口（just sw 内嵌 / just hm 独立）各自评估任务声明，生成逻辑必须单源，
# 否则同一份声明在两个入口行为漂移。
{
  lib,
  pkgs,
  homeDir,
}:
rec {
  # 补默认值（对应 darwin 层 taskType submodule 的默认语义）
  # 注意 `//` 顺序：默认值在后，覆盖裸声明缺省字段，保留显式值
  withDefaults =
    t:
    t
    // {
      user = t.user or true;
      when = if builtins.isString (t.when or null) then [ t.when ] else (t.when or [ ]);
      every = t.every or null;
      packages = t.packages or [ ];
      secrets = t.secrets or { };
    };

  # 任务字段白名单（对齐 darwin 层 taskType 选项）
  taskFields = [
    "when"
    "every"
    "user"
    "packages"
    "secrets"
    "script"
  ];

  # 校验裸声明：拒绝未知字段 + when/every 互斥。home 层不走 submodule，
  # 必须显式校验，否则拼写错误会静默按默认值部署
  checkTask =
    name: t:
    let
      unknown = builtins.filter (k: !(builtins.elem k taskFields)) (builtins.attrNames t);
    in
    if unknown != [ ] then
      throw "task '${name}': 未知字段 ${builtins.toString unknown}（合法: ${builtins.concatStringsSep ", " taskFields}）"
    else if (t.when or [ ]) != [ ] && (t.every or null) != null then
      throw "task '${name}': when 与 every 必须二选一"
    else
      t;

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

  # 任务包装脚本：起止时间戳日志 + 失败通知（仅 launchd 触发且非零退出才通知）
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
        '') (t.secrets or { })
      );
    in
    pkgs.writeShellApplication {
      name = "task-${name}";
      runtimeInputs = t.packages or [ ];
      text = ''
        __on_exit() {
          local code=$?
          local end_time
          end_time=$(date '+%Y-%m-%d %H:%M:%S')
          echo "[$end_time] ===== Task '${name}' Finished (exit code: $code) ====="
          ${lib.optionalString (t.user or true) ''
            # 仅 launchd 触发且非零退出才发通知；手动 task run 调试保持静默
            if [ "$code" -ne 0 ] && [ -n "''${XPC_SERVICE_NAME:-}" ]; then
              ${pkgs.terminal-notifier}/bin/terminal-notifier \
                -title "Task Failed: ${name}" \
                -message "退出码 ''${code}, 点击查看日志" \
                -sound Basso \
                -group "task-${name}" \
                -open "file://${homeDir}/Library/Logs/task-${name}.log" \
                2>/dev/null || true
            fi
          ''}
        }
        trap __on_exit EXIT

        ${secretExports}

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== Task '${name}' Started ====="

        ${t.script}
      '';
    };

  # 启用过滤（有调度才生成，无 when/every 的任务声明视为未启用）
  enabled = lib.filterAttrs (_: t: (t.when or [ ]) != [ ] || t.every != null);

  # user 任务（home 层 agent）
  userTasks = tasks: lib.filterAttrs (_: t: (t.user or true)) (enabled tasks);

  # root 任务（darwin 层 daemon）
  rootTasks = tasks: lib.filterAttrs (_: t: !(t.user or true)) (enabled tasks);
}
