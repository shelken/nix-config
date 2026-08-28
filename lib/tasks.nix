# 任务系统共享核心：darwin 层（root daemon + task CLI）与 home 层（user agent）共用。
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
    };

  # 任务字段白名单（对齐 darwin 层 taskType 选项）
  taskFields = [
    "when"
    "every"
    "user"
    "packages"
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

  # 任务包装脚本：起止时间戳日志 + 失败通知（仅 launchd 触发且非零退出才通知）
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
                -open "file://${homeDir}/Library/Logs/task-${name}.log" \
                2>/dev/null || true
            fi
          ''}
        }
        trap __on_exit EXIT

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
