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

  # 策略收敛体：ignores 先比对再写（无变化不产生写操作），压缩与保留每次幂等声明
  policySyncBody = ''
    ${repoCheck}

    current=$(${pkgs.kopia}/bin/kopia policy export "${target}" 2>/dev/null) || {
      # target 不存在是首次部署的正常状态（交给 policy set 创建）；其他错误则终止
      if ${pkgs.kopia}/bin/kopia policy export "${target}" 2>&1 | grep -q "policy not found"; then
        current=""
      else
        echo "Failed to read policy for ${target}" >&2
        exit 1
      fi
    }
    currentIgnores=$(printf '%s' "''${current:-}" | ${pkgs.jq}/bin/jq -c '."${target}".files.ignore // [] | sort') || {
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

  # 维护体：每天让策略收敛一次（幂等、无变化不写），全量维护只在周日执行。
  # 维护任务天天调度，脚本自己判日，因此手动运行也安全
  maintenanceBody = ''
    ${policySyncBody}

    if [ "$(date +%u)" -ne 7 ]; then
      echo "Not Sunday, skipping full maintenance"
      exit 0
    fi
    ${pkgs.kopia}/bin/kopia maintenance run --full
  '';

  # CLI 入口共用前置：手动运行时自行解密口令并指向仓库配置
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
        jitter = 600;
        island = true;
        packages = [ pkgs.kopia ];
        env = {
          KOPIA_CONFIG_PATH = kopiaConfigPath;
        };
        secrets = {
          KOPIA_PASSWORD = kopiaPasswordPath;
        };
        notify.title = "Kopia Maintenance";
        script = maintenanceBody;
      };
    };

    home.packages = [
      pkgs.kopia
      (mkKopiaCli {
        name = "kopia-backup";
        runtimeInputs = [ pkgs.kopia ];
        body = backupBody;
      })
      (mkKopiaCli {
        name = "kopia-maintenance";
        runtimeInputs = [ pkgs.kopia ];
        body = maintenanceBody;
      })
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
