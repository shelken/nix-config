{
  config,
  pkgs,
  lib,
  mylib,
  myvars,
  hostname,
  ...
}:
let
  cfg = config.shelken.backup;
  effectivePaths = cfg.backupPaths ++ (lib.concatLists (lib.attrValues cfg.app));
  backupScript = pkgs.writeShellScript "kopia-backup.sh" ''
    notify() {
      /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" || true
    }

    log() {
      ${pkgs.gum}/bin/gum log -l "$1" -t rfc3339 -s "$2" "''${@:3}"
    }
    if [ -z $KOPIA_PASSWORD_FILE ]; then
      log error "KOPIA_PASSWORD_FILE 缺失"
      exit 1
    fi
    export KOPIA_PASSWORD=$(cat $KOPIA_PASSWORD_FILE)
    userAtHost="${myvars.username}@${hostname}"

    log info "=== Backup Started ==="

    # 添加随机延迟，防止多设备同时触发（0-10分钟随机）
    # 如果 CANCEL_RANDOM=true 则跳过随机延迟
    if [ "$CANCEL_RANDOM" != "true" ]; then
      random_delay=$(od -An -N2 -t u2 /dev/urandom | xargs | awk '{print $1 % 600}')
      log info "Random delay: $random_delay seconds（如果要跳过 delay 设置 CANCEL_RANDOM=true）"
      sleep $random_delay
    else
      log info "Random delay skipped (CANCEL_RANDOM=true)"
    fi

    log debug "KOPIA_PASSWORD_FILE: $KOPIA_PASSWORD_FILE"
    log debug "KOPIA_CONFIG_PATH: $KOPIA_CONFIG_PATH"
    # 检查仓库连接
    ${pkgs.kopia}/bin/kopia repository status &>/dev/null || {
      log error "Repository not connected"
      #notify "Kopia Backup Failed" "Repository not connected"
      exit 1
    }

    # 配置策略
    log info "Setting up backup policies"

    # 应用配置的策略（跳过 global 策略）
    ${toString (
      lib.concatMapStringsSep "\n" (policyName: ''
        ${lib.optionalString (policyName != "global") ''
          log info "Applying policy: ${policyName}"
          ${pkgs.kopia}/bin/kopia policy set \
            ${lib.optionalString (policyName == "global") "--global"} \
            ${lib.optionalString (policyName != "global") "\"${policyName}\""} \
            --compression="${cfg.policy."${policyName}".compression}" \
            ${
              toString (
                lib.concatMapStringsSep " \\\n          " (ignore: "--add-ignore \"${ignore}\"") (
                  cfg.policy."${policyName}".ignores
                )
              )
            } \
            ${
              toString (
                lib.concatMapStringsSep " \\\n          " (
                  retentionType:
                  "--keep-${retentionType} ${toString (cfg.policy."${policyName}".retention."${retentionType}")}"
                ) (builtins.attrNames cfg.policy."${policyName}".retention)
              )
            } || {
            log warn "Failed to set policy for ${policyName}"
          }
        ''}
      '') (builtins.attrNames cfg.policy)
    )}

    # 检查是否有备份路径
    if [ ${toString (builtins.length effectivePaths)} -eq 0 ]; then
      log info "No backup paths configured, skipping backup"
      exit 0
    fi

    # 执行备份
    for dir in ${toString effectivePaths}; do
      # 检查路径是否存在
      if [ ! -e "$dir" ]; then
        log warn "Path does not exist, skipping: $dir"
        continue
      fi

      log info "Backing up: $dir"
      ${pkgs.kopia}/bin/kopia snapshot create \
        "$dir" \
        --tags=type:automated \
        --progress || {
        log error "Backup failed for $dir"
        notify "Kopia Backup Failed" "Backup failed for $dir"
        exit 1
      }
    done

    # 每周日维护
    if [ "$(date +%u)" -eq 7 ]; then
      log info "Running full maintenance..."
      ${pkgs.kopia}/bin/kopia maintenance run --full || {
        log warn "Maintenance failed"
        notify "Kopia Backup Warning" "Maintenance failed"
      }
    fi

    log info "=== Backup Completed ==="
    # notify "Kopia Backup" "Backup completed successfully"
  '';
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.all (p: lib.hasPrefix "/" p) effectivePaths;
        message = "shelken.backup: 所有备份路径必须是绝对路径（以 / 开头），请检查 backupPaths 和 backup.app 的配置";
      }
    ];

    home.packages = with pkgs; [
      kopia
      (writeShellApplication {
        name = "kopia-backup";
        runtimeInputs = [
          kopia
          gum
        ];
        text = ''
          # 设置环境变量（如果未设置）
          export KOPIA_PASSWORD_FILE="''${KOPIA_PASSWORD_FILE:-"${config.sops.secrets.kopia-password.path}"}"
          export KOPIA_CONFIG_PATH="''${KOPIA_CONFIG_PATH:-"${
            config.sops.templates."kopia-repository.config".path
          }"}"
          ${backupScript}
        '';
      })
      (writeShellApplication {
        name = "kopia-ui";
        runtimeInputs = [ kopia ];
        text = ''
          KOPIA_PASSWORD="$(cat "''${KOPIA_PASSWORD_FILE:-"${config.sops.secrets.kopia-password.path}"}")"
          export KOPIA_PASSWORD
          export KOPIA_CONFIG_PATH="''${KOPIA_CONFIG_PATH:-"${
            config.sops.templates."kopia-repository.config".path
          }"}"
          echo "Starting Kopia UI at http://localhost:51515"
          kopia server start --ui --insecure --without-password "$@"
        '';
      })
    ];

    launchd.agents.kopia-backup = mylib.mkLaunchCommand {
      name = "kopia-backup";
      commandFile = backupScript;
      config = {
        RunAtLoad = false;
        Debug = true;
        KeepAlive = false;
        StartCalendarInterval = cfg.calendarInterval;
        EnvironmentVariables = {
          KOPIA_PASSWORD_FILE = "${config.sops.secrets.kopia-password.path}";
          KOPIA_CONFIG_PATH = "${config.sops.templates."kopia-repository.config".path}";
        };
      };
    };
  };
}
