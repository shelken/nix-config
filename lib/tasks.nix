{
  lib,
  pkgs,
  homeDir,
  opTokenFile,
}:
let
  launchdEnv = "SHELKEN_TASK_LAUNCHD";
in
rec {
  taskDefaults = {
    enable = true;
    user = true;
    when = [ ];
    weekday = [ ];
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
  };

  labelPrefix = "space.ooooo.task-";

  logPath =
    name: t:
    if t.user then "${homeDir}/Library/Logs/task-${name}.log" else "/Library/Logs/task-${name}.log";

  mkLaunchdConfig =
    name: t:
    {
      Label = "${labelPrefix}${name}";
      RunAtLoad = false;
      KeepAlive = false;
      EnvironmentVariables = {
        ${launchdEnv} = "1";
      };
      StandardOutPath = logPath name t;
      StandardErrorPath = logPath name t;
    }
    // mkTrigger t;

  mkAssertions =
    tasks:
    lib.concatLists (
      lib.mapAttrsToList (name: t: [
        {
          assertion = !(t.when != [ ] && t.every != null);
          message = "shelken.tasks.${name}: when 与 every 不能同时设置";
        }
        {
          assertion = t.weekday == [ ] || (t.when != [ ] && t.every == null);
          message = "shelken.tasks.${name}: weekday 必须配合 when 使用，不能与 every 共用";
        }
      ]) tasks
    );

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
    else if t.when == [ ] then
      { }
    else
      {
        StartCalendarInterval =
          if t.weekday == [ ] then
            map parseTime t.when
          else
            lib.concatMap (day: map (time: (parseTime time) // { Weekday = day; }) t.when) t.weekday;
      };

  mkPackage =
    name: t:
    let
      isOpRef = lib.hasPrefix "op://";

      readFileSecret = var: secretPath: ''
        if [ ! -r "${secretPath}" ]; then
          echo "Task '${name}': required secret ${var} is not readable: ${secretPath}" >&2
          exit 1
        fi
        ${var}="$(<"${secretPath}")"
        export ${var}
      '';

      readOpSecret = var: ref: ''
        if [ ! -r "${opTokenFile}" ]; then
          echo "Task '${name}': 1Password service account token is not readable: ${opTokenFile}" >&2
          exit 1
        fi
        if ! ${var}="$(OP_SERVICE_ACCOUNT_TOKEN="$(<"${opTokenFile}")" ${pkgs._1password-cli}/bin/op read ${lib.escapeShellArg ref})"; then
          echo "Task '${name}': failed to resolve secret ${var} from ${ref}" >&2
          exit 1
        fi
        export ${var}
      '';

      secretExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          var: value: if isOpRef value then readOpSecret var value else readFileSecret var value
        ) t.secrets
      );

      # 不用单引号包裹是为了避开 shellcheck 的 SC2016（连 info 级都会让构建失败）
      quoteDouble = s: builtins.replaceStrings [ "\\" "\"" "$" "`" ] [ "\\\\" "\\\"" "\\$" "\\`" ] s;

      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (var: value: ''export ${var}="${quoteDouble value}"'') t.env
      );

      jitterBlock = lib.optionalString (t.jitter != null) ''
        if [ "''${${launchdEnv}:-}" = "1" ]; then
          jitter=$(( RANDOM % ${toString t.jitter} ))
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Jitter delay: ''${jitter}s"
          sleep "$jitter"
        fi
      '';

      runnerBin = pkgs.writeShellScript "task-${name}-runner" ''
        ${secretExports}
        ${envExports}
        trigger=manual
        [ "''${${launchdEnv}:-}" = "1" ] && trigger=launchd
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ===== Task '${name}' Started ($trigger) ====="
        ${t.script}
      '';

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
            -open "file://${logPath name t}" \
            2>/dev/null || true
        '';

      notifyOnExit =
        if !t.user || !(t.notify.failure || t.notify.success) then
          ""
        else
          ''
            if [ "''${${launchdEnv}:-}" = "1" ]; then
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
          ${notifyOnExit}
        }
        trap __on_exit EXIT

        ${jitterBlock}
        "${runnerBin}"
      '';
    };

  mkTaskType =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = taskDefaults.enable;
          description = "是否部署任务；false 保留声明，但不生成 launchd job 与手动命令";
        };
        when = lib.mkOption {
          type = lib.types.coercedTo lib.types.str (t: [ t ]) (lib.types.listOf lib.types.str);
          default = taskDefaults.when;
          description = "日历时间 HH:MM（launchd StartCalendarInterval，睡眠错过唤醒后补跑）";
          example = "3:15";
        };
        weekday = lib.mkOption {
          type = lib.types.listOf (lib.types.ints.between 0 7);
          default = taskDefaults.weekday;
          description = "when 的星期限制，空列表表示每天；0 与 7 都是周日，不能用于 every 或纯手动任务";
          example = [ 0 ];
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
          description = "任务需要的环境变量到凭据来源的映射：sops 解密文件路径，或 op:// 引用（经 service account 从 1Password 读取）";
          example = lib.literalExpression ''
            {
              GH_TOKEN = secretPath "github/cli-token";
              MAGPIE_API_KEY = "op://Agent/MAGPIE_API_KEY/credential";
            }
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
          type = lib.types.nullOr (lib.types.ints.between 1 32767);
          default = taskDefaults.jitter;
          description = "launchd 调度触发时的最大随机延迟秒数（1 到 32767，上限来自 bash RANDOM），手动运行不延迟";
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
        package = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = "生成的可执行脚本（内部用）";
        };
      };
      config = {
        package = mkPackage name config;
      };
    };

  enabled = tasks: lib.filterAttrs (_: t: t.enable) tasks;

  userTasks = tasks: lib.filterAttrs (_: t: t.user) (enabled tasks);

  rootTasks = tasks: lib.filterAttrs (_: t: !t.user) (enabled tasks);
}
