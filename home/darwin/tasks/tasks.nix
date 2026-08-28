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
  taskCfg = mylib.loadTasks (mylib.relativeToRoot "hosts/${hostname}/tasks") {
    inherit pkgs lib;
  };

  # 补默认值（与 modules/darwin/tasks/task.nix 的 taskType submodule 一致）
  withDefaults =
    t:
    t
    // {
      user = t.user or true;
      when = if builtins.isString (t.when or null) then [ t.when ] else (t.when or [ ]);
      every = t.every or null;
      packages = t.packages or [ ];
    };

  tasks = lib.mapAttrs (_: t: withDefaults t) taskCfg;

  # 与 modules/darwin/tasks/task.nix 的 taskType 相同（root daemon 分支用 darwin 层那份）
  parseTime =
    t:
    let
      parts = lib.splitString ":" t;
    in
    {
      Hour = lib.toIntBase10 (lib.elemAt parts 0);
      Minute = lib.toIntBase10 (lib.elemAt parts 1);
    };

  mkTrigger =
    t:
    if t.every != null then
      { StartInterval = t.every; }
    else
      { StartCalendarInterval = map parseTime t.when; };

  userHome = config.home.homeDirectory;

  mkPackage =
    name: t:
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
            if [ "$code" -ne 0 ] && [ -n "$XPC_SERVICE_NAME" ]; then
              ${pkgs.terminal-notifier}/bin/terminal-notifier \
                -title "Task Failed: ${name}" \
                -message "退出码 ''${code}, 点击查看日志" \
                -sound Basso \
                -group "task-${name}" \
                -open "file://${userHome}/Library/Logs/task-${name}.log" \
                2>/dev/null || true
            fi
          ''}
        }
        trap __on_exit EXIT

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== Task '${name}' Started ====="

        ${t.script}
      '';
    };

  userTasks = lib.filterAttrs (_: t: (t.user or true) && (t.when != [ ] || t.every != null)) tasks;
in
{
  launchd.agents = lib.mapAttrs (
    name: t:
    mylib.mkLaunchCommand {
      inherit name;
      commandFile = "${mkPackage name t}/bin/task-${name}";
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

  home.packages = lib.mapAttrsToList mkPackage userTasks;
}
