{
  config,
  pkgs,
  lib,
  myvars,
  hostname,
  ...
}:
let
  cfg = config.shelken.backup;
  effectivePaths = cfg.backupPaths ++ (lib.concatLists (lib.attrValues cfg.app));
  effectiveIgnores = lib.naturalSort (lib.unique (cfg.policy.ignores ++ cfg.ignores));
  target = "${myvars.username}@${hostname}";

  kopiaConfigPath = config.sops.templates."kopia-repository.config".path;
  kopiaPasswordPath = config.sops.secrets.kopia-password.path;

  # 连接检查：所有 kopia 操作的前提，快照/策略/维护三条命令共用
  repoCheck = ''
    ${pkgs.kopia}/bin/kopia repository status &>/dev/null || {
      echo "Kopia repository not connected" >&2
      exit 1
    }
  '';

  # 快照体：只做逐路径快照。策略收敛与全量维护不在快照热路径上
  backupBody = ''
    ${repoCheck}

    # 目标策略还没落进这个库（首次部署或新设备）时先同步一次，
    # 否则首个快照会按默认策略把 node_modules、target、.build 之类一并传上去
    if ! ${pkgs.kopia}/bin/kopia policy export "${target}" >/dev/null 2>&1; then
      ${policySyncCore}
    fi

    ${lib.optionalString (effectivePaths == [ ]) ''
      echo "No backup paths configured, skipping backup"
      exit 0
    ''}
    ${lib.optionalString (effectivePaths != [ ]) ''
      for dir in ${toString effectivePaths}; do
        if [ ! -e "$dir" ]; then
          echo "Path does not exist, skipping: $dir"
          continue
        fi
        echo "Backing up: $dir"
        ${pkgs.kopia}/bin/kopia snapshot create "$dir" \
          --tags=type:automated \
          --progress || {
          echo "Backup failed for $dir" >&2
          exit 1
        }
      done
    ''}
  '';

  # 策略收敛核心：ignores 先比对再写（无变化不产生写操作），压缩与保留每次幂等声明。
  # 快照前补同步与独立命令共用，因此不含仓库连接检查
  policySyncCore = ''
    # 一次 export 同时拿输出和退出码：写成 cmd | grep 时，管道在 pipefail 下整体判失败，
    # 首次部署（目标策略还不存在）会被误判成读取失败
    policyJson=""
    if ! policyJson=$(${pkgs.kopia}/bin/kopia policy export "${target}" 2>&1); then
      case "$policyJson" in
        *"policy not found"*)
          # 首次部署的正常状态，交给下面的 policy set 创建
          policyJson=""
          ;;
        *)
          echo "$policyJson" >&2
          exit 1
          ;;
      esac
    fi
    currentIgnores=$(printf '%s' "$policyJson" | ${pkgs.jq}/bin/jq -c '."${target}".files.ignore // [] | sort') || {
      echo "Failed to parse policy for ${target}" >&2
      exit 1
    }

    if [ "$currentIgnores" = '${builtins.toJSON effectiveIgnores}' ]; then
      echo "Ignores for ${target} up to date, skipping."
    else
      echo "Updating ignores for ${target}..."
      ${pkgs.kopia}/bin/kopia policy set "${target}" --clear-ignore || exit 1
      ${lib.optionalString (effectiveIgnores != [ ]) ''
        ${pkgs.kopia}/bin/kopia policy set "${target}" \
          ${
            toString (
              lib.concatMapStringsSep " \\\n          " (ignore: "--add-ignore \"${ignore}\"") effectiveIgnores
            )
          } || exit 1
      ''}
    fi

    ${pkgs.kopia}/bin/kopia policy set "${target}" \
      --compression="${cfg.policy.compression}" \
      ${
        toString (
          lib.concatMapStringsSep " \\\n      " (
            retentionType: "--keep-${retentionType} ${toString (cfg.policy.retention.${retentionType})}"
          ) (builtins.attrNames cfg.policy.retention)
        )
      } || exit 1
  '';

  policySyncBody = ''
    ${repoCheck}

    ${policySyncCore}
  '';

  # 维护体：每天让策略收敛一次（幂等、无变化不写）。全量维护只在周日跑，但那个门禁
  # 只管定时调度：手动运行 kopia-maintenance 时应当真的执行维护，随时可用
  maintenanceBody = ''
    ${repoCheck}

    ${policySyncCore}

    if [ "''${SHELKEN_TASK_LAUNCHD:-}" = "1" ] && [ "$(date +%u)" -ne 7 ]; then
      echo "Not Sunday, skipping scheduled full maintenance"
      exit 0
    fi
    ${pkgs.kopia}/bin/kopia maintenance run --full
  '';

  # 手动入口共用前置：自行解密口令并指向仓库配置
  cliPrelude = ''
    KOPIA_PASSWORD="$(cat "''${KOPIA_PASSWORD_FILE:-"${kopiaPasswordPath}"}")"
    export KOPIA_PASSWORD
    KOPIA_CONFIG_PATH="''${KOPIA_CONFIG_PATH:-"${kopiaConfigPath}"}"
    export KOPIA_CONFIG_PATH
  '';

  mkKopiaCli =
    {
      name,
      runtimeInputs,
      body,
    }:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = cliPrelude + body;
    };

  # 定时任务的手动入口：直接 exec 任务脚本，口令注入、日志与退出码都由任务包装提供，
  # 不再各留一份实现，避免两条路径的 shell 严格模式差异
  mkTaskAlias =
    name:
    pkgs.writeShellApplication {
      inherit name;
      text = ''exec ${config.shelken.tasks.${name}.package}/bin/task-${name} "$@"'';
    };
in
{
  config = {
    assertions = [
      {
        assertion = builtins.all (p: lib.hasPrefix "/" p) effectivePaths;
        message = "shelken.backup: 所有备份路径必须是绝对路径（以 / 开头），请检查 backupPaths 和 backup.app 的配置";
      }
    ];

    # 定时快照与维护接入 shelken.tasks：调度、抖动、日志、灵动岛与失败通知全部由任务系统提供
    shelken.tasks = {
      kopia-backup = {
        when = cfg.calendarInterval;
        jitter = 600;
        island = true;
        packages = [ pkgs.kopia ];
        env = {
          KOPIA_CONFIG_PATH = kopiaConfigPath;
        };
        secrets = {
          KOPIA_PASSWORD = kopiaPasswordPath;
        };
        notify.title = "Kopia Backup";
        script = backupBody;
      };
      kopia-maintenance = {
        when = cfg.maintenanceWhen;
        packages = [ pkgs.kopia ];
        env.KOPIA_CONFIG_PATH = kopiaConfigPath;
        secrets.KOPIA_PASSWORD = kopiaPasswordPath;
        notify.title = "Kopia Maintenance";
        script = maintenanceBody;
      };
    };

    home.packages = [
      pkgs.kopia
      (mkTaskAlias "kopia-backup")
      (mkTaskAlias "kopia-maintenance")
      (mkKopiaCli {
        name = "kopia-policy-sync";
        runtimeInputs = [
          pkgs.kopia
          pkgs.jq
        ];
        body = policySyncBody;
      })
      (mkKopiaCli {
        name = "kopia-ui";
        runtimeInputs = [ pkgs.kopia ];
        body = ''
          echo "Starting Kopia UI at http://localhost:51515"
          kopia server start --ui --insecure --without-password "$@"
        '';
      })
    ];
  };
}
