{
  mylib,
  lib,
  myvars,
  hostname,
  ...
}:
let
  policyDefaults = import ./policy-defaults.nix { inherit hostname myvars; };
  defaultPolicy = policyDefaults."${myvars.username}@${hostname}";
in
{
  imports = [
    ./secrets.nix
    ./service.nix
  ];

  # 默认配置：
  # - enable 关闭
  # - calendarInterval 每天两次，时间按 hostname 固定分布
  # - policy 默认值见 ./policy-defaults.nix
  # enable/app/backupPaths/ignores 声明在 home/base/core/backup-options.nix（全平台共享），
  # 本文件只声明 kopia 后端自身的选项
  options.shelken.backup = {
    calendarInterval = lib.mkOption {
      type = with lib.types; listOf (attrsOf int);
      default =
        let
          schedule = mylib.calcUniformSchedule {
            inherit hostname;
            startHour = 2;
            endHour = 8;
          };
        in
        [
          {
            Hour = schedule.hour;
            Minute = schedule.minute;
          }
          {
            Hour = schedule.hour + 12;
            Minute = schedule.minute;
          }
        ];
      description = "启动日历间隔，定义备份执行的时间";
      example = [
        {
          Hour = 2;
          Minute = 30;
        }
        {
          Hour = 14;
          Minute = 45;
        }
      ];
    };
    policy = lib.mkOption {
      type =
        with lib.types;
        attrsOf (
          lib.types.submodule {
            options = {
              compression = lib.mkOption {
                type = lib.types.str;
                default = defaultPolicy.compression;
                description = "压缩算法";
                example = "zstd-fastest";
              };
              ignores = lib.mkOption {
                type = with lib.types; listOf str;
                default = defaultPolicy.ignores;
                description = "忽略模式列表";
                example = [
                  "*.tmp"
                  "node_modules"
                  "*.log"
                ];
              };
              retention = lib.mkOption {
                type = with lib.types; attrsOf lib.types.int;
                default = defaultPolicy.retention;
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
      default = policyDefaults;
      description = ''
        备份策略配置，不支持 global 配置。
        默认策略定义在 ./policy-defaults.nix。
      '';
      example = {
        "user@host" = {
          compression = "zstd-fastest";
          ignores = [
            "node_modules"
            ".cache"
          ];
        };
        "user@host:/specific/path" = {
          retention = {
            daily = 30;
          };
        };
      };
    };
  };
}
