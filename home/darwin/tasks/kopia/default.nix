{
  mylib,
  config,
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
  # - backupPaths / app 为空
  # - calendarInterval 每天两次，时间按 hostname 固定分布
  # - policy 默认值见 ./policy-defaults.nix
  options.shelken.backup = {
    enable = mylib.mkBoolOpt false "是否开启备份";
    app = lib.mkOption {
      type = with lib.types; attrsOf (listOf str);
      default = { };
      description = "各 app 模块自己声明的备份路径，key 为 app 名";
      example = {
        pi = [ "\${config.home.homeDirectory}/.config/pi" ];
      };
    };
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
