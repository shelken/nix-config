{
  mylib,
  config,
  pkgs,
  myvars,
  hostname,
  lib,
  ...
}:
let
  cfg = config.shelken.backup;
  backupScript = pkgs.writeShellScript "kopia-backup.sh" ''
    #!/usr/bin/env bash

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

    # 检查仓库连接
    ${pkgs.kopia}/bin/kopia repository status &>/dev/null || {
      log error "Repository not connected"
      #notify "Kopia Backup Failed" "Repository not connected"
      exit 1
    }

    # 配置策略
    log info "Setting up backup policies"

    # 应用配置的策略
    ${toString (
      lib.concatMapStringsSep "\n" (policyName: ''
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
      '') (builtins.attrNames cfg.policy)
    )}

    # 检查是否有备份路径
    if [ ${toString (builtins.length cfg.backupPaths)} -eq 0 ]; then
      log info "No backup paths configured, skipping backup"
      exit 0
    fi

    # 执行备份
    for dir in ${toString cfg.backupPaths}; do
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
  options.shelken.backup = {
    enable = mylib.mkBoolOpt false "是否开启备份";
    backupPaths = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "要备份的路径列表（文件或目录）";
      example = [
        ''"''${config.home.homeDirectory}/Documents"''
        ''"''${config.home.homeDirectory}/Pictures"''
        ''"''${config.home.homeDirectory}/important-file.txt"''
      ];
    };
    #TODO 增加删除处理
    policy = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          lib.types.submodule {
            options = {
              compression = lib.mkOption {
                type = lib.types.str;
                default = "zstd-fastest";
                description = "压缩算法";
                example = "zstd-fastest";
              };
              ignores = lib.mkOption {
                type = with lib.types; listOf str;
                default = [
                  "*.tmp"
                  ".direnv"
                  ".venv"
                  ".vitepress"
                  "*.temp"
                  "*.log"
                  "*.cache"
                  "node_modules"
                  "dist"
                  "*.DS_Store"
                  ".DS_Store?"
                  "._*"
                  ".Spotlight-V100"
                  ".Trashes"
                  "Thumbs.db"
                ];
                description = "忽略模式列表";
                example = [
                  "*.tmp"
                  "node_modules"
                  "*.log"
                ];
              };
              retention = lib.mkOption {
                type = with lib.types; attrsOf lib.types.int;
                default = {
                  latest = 48;
                  daily = 30;
                  weekly = 12;
                  monthly = 12;
                };
                description = "保留策略";
                example = {
                  latest = 24;
                  daily = 7;
                  weekly = 4;
                };
              };
            };
          }
        );
      default = {
        "${myvars.username}@${hostname}" = { };
      };
      description = "备份策略配置";
      example = {
        global = {
          compression = "zstd";
          ignores = [
            "*.tmp"
            "*.log"
          ];
          retention = {
            latest = 24;
            daily = 7;
          };
        };
        "user@host" = {
          compression = "zstd-fastest";
          ignores = [
            "node_modules"
            ".cache"
          ];
        };
        "/specific/path" = {
          retention = {
            daily = 30;
          };
        };
      };
    };

  };
  config = lib.mkIf cfg.enable {
    # 使用工具 及 开启secret
    shelken.tools.backup.enable = true;
    shelken.secrets.enable = true;

    # sops.secrets.kopia-webdav-url = mylib.mkDefaultSecret { key = "drive/url"; };
    # sops.secrets.kopia-webdav-password = mylib.mkDefaultSecret { key = "drive/rclone/pass"; };

    sops.secrets.kopia-password = mylib.mkDefaultSecret { key = "kopia/password"; };
    sops.secrets.kopia-s3-host = mylib.mkDefaultSecret { key = "drive/s3/host"; };
    sops.secrets.kopia-s3-access-key-id = mylib.mkDefaultSecret { key = "drive/s3/access_key_id"; };
    sops.secrets.kopia-s3-secret-access-key = mylib.mkDefaultSecret {
      key = "drive/s3/secret_access_key";
    };

    ## NOTE: 在此说明， kopia 的 s3与文件系统 存储结构不同，因此不同repo创建的无法直接连接，必须使用不同repo，
    ## 不同repo之间同步使用子命令`repository sync-to`
    # sops.templates."kopia-repository.config" = {
    #   content = ''
    #     {
    #       "storage": {
    #         "type": "webdav",
    #         "config": {
    #           "url": "${config.sops.placeholder.kopia-webdav-url}/dav/cloud/189/backup/kopia/main-webdav",
    #           "username": "rclone",
    #           "password": "${config.sops.placeholder.kopia-webdav-password}",
    #           "atomicWrites": false,
    #           "dirShards": null
    #         }
    #       },
    #       "hostname": "mio",
    #       "username": "${myvars.username}",
    #       "description": "",
    #       "enableActions": false
    #     }
    #   '';
    #   # path = "${config.xdg.configHome}/kopia/kopia-repository.config";
    #   mode = "0500";
    # };
    sops.templates."kopia-repository.config" = {
      content = ''
        {
          "storage": {
            "type": "s3",
            "config": {
              "bucket": "kopia",
              "prefix": "main/",
              "endpoint": "${config.sops.placeholder.kopia-s3-host}",
              "doNotUseTLS": false,
              "accessKeyID": "${config.sops.placeholder.kopia-s3-access-key-id}",
              "secretAccessKey": "${config.sops.placeholder.kopia-s3-secret-access-key}"
            }
          },
          "caching": {
            "cacheDirectory": "${config.xdg.cacheHome}/kopia/main",
            "maxCacheSize": 5242880000,
            "maxMetadataCacheSize": 5242880000,
            "maxListCacheDuration": 30
           },
          "hostname": "${hostname}",
          "username": "${myvars.username}",
          "description": "Repository in S3: ${config.sops.placeholder.kopia-s3-host} kopia:main/",
          "enableActions": false,
          "formatBlobCacheDuration": 900000000000
        }
      '';
      mode = "0500";
    };
    launchd.agents.kopia-backup = mylib.mkLaunchCommand {
      name = "kopia-backup";
      commandFile = backupScript;
      config = {
        RunAtLoad = false;
        Debug = false;
        KeepAlive = false;
        # 每 6h 运行
        StartCalendarInterval = [
          {
            Hour = 1;
            Minute = 0;
          }
          {
            Hour = 7;
            Minute = 0;
          }
          {
            Hour = 13;
            Minute = 0;
          }
          {
            Hour = 19;
            Minute = 0;
          }
        ];
        EnvironmentVariables = {
          KOPIA_PASSWORD_FILE = "${config.sops.secrets.kopia-password.path}";
          KOPIA_CONFIG_PATH = "${config.sops.templates."kopia-repository.config".path}";
        };
      };
    };
  };

}
