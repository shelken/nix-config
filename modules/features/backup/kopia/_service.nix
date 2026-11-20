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

  repoCheck = ''
    ${pkgs.kopia}/bin/kopia repository status &>/dev/null || {
      echo "Kopia repository not connected" >&2
      exit 1
    }
  '';

  backupBody = ''
    ${repoCheck}

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

  policySyncCore = ''
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

  # 只做手动入口：共享 main 仓库的维护所有者是 sakamoto 上常驻的 kopia server，
  # 它按自身计划跑快速与全量维护；其他客户端执行会被 kopia 以非所有者拒绝
  maintenanceBody = ''
    ${repoCheck}

    ${pkgs.kopia}/bin/kopia maintenance run --full
  '';

  cliPrelude = ''
    KOPIA_PASSWORD="$(cat "''${KOPIA_PASSWORD_FILE:-"${kopiaPasswordPath}"}")"
    export KOPIA_PASSWORD
    KOPIA_CONFIG_PATH="''${KOPIA_CONFIG_PATH:-"${kopiaConfigPath}"}"
    export KOPIA_CONFIG_PATH
  '';

in
{
  config = {
    assertions = [
      {
        assertion = builtins.all (p: lib.hasPrefix "/" p) effectivePaths;
        message = "shelken.backup: 所有备份路径必须是绝对路径（以 / 开头），请检查 backupPaths 和 backup.app 的配置";
      }
    ];

    shelken.tasks = {
      kopia-backup = {
        when = cfg.calendarInterval;
        jitter = 600;
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
      kopia-policy-sync = {
        when = cfg.policySyncWhen;
        weekday = [ 0 ];
        packages = [ pkgs.kopia ];
        env.KOPIA_CONFIG_PATH = kopiaConfigPath;
        secrets.KOPIA_PASSWORD = kopiaPasswordPath;
        notify.title = "Kopia Policy Sync";
        script = policySyncBody;
      };
    };

    home.packages = [
      pkgs.kopia
      (pkgs.writeShellApplication {
        name = "kopia-maintenance";
        text = cliPrelude + maintenanceBody;
      })
      (pkgs.writeShellApplication {
        name = "kopia-ui";
        runtimeInputs = [ pkgs.kopia ];
        text = cliPrelude + ''
          echo "Starting Kopia UI at http://localhost:51515"
          kopia server start --ui --insecure --without-password "$@"
        '';
      })
    ]
    ++ lib.optional config.shelken.tasks.kopia-backup.enable (
      pkgs.writeShellApplication {
        name = "kopia-backup";
        text = ''
          if [ "''${1:-}" = "--dry-run" ]; then
            ${cliPrelude}
            for dir in ${lib.escapeShellArgs effectivePaths}; do
              ${pkgs.kopia}/bin/kopia snapshot estimate --quiet "$dir"
            done
          else
            exec ${config.shelken.tasks.kopia-backup.package}/bin/task-kopia-backup "$@"
          fi
        '';
      }
    )
    ++ lib.optional config.shelken.tasks.kopia-policy-sync.enable (
      pkgs.writeShellApplication {
        name = "kopia-policy-sync";
        text = ''exec ${config.shelken.tasks.kopia-policy-sync.package}/bin/task-kopia-policy-sync "$@"'';
      }
    );
  };
}
