{
  mylib,
  lib,
  hostname,
  ...
}:
let
  policyDefaults = import ./_policy-defaults.nix;
in
{
  imports = [
    ./_secrets.nix
    ./_service.nix
  ];

  options.shelken.backup = {
    calendarInterval = lib.mkOption {
      type = with lib.types; listOf str;
      default =
        let
          schedule = mylib.calcUniformSchedule {
            inherit hostname;
            startHour = 2;
            endHour = 8;
          };
          pad = n: lib.fixedWidthString 2 "0" (toString n);
        in
        [
          "${pad schedule.hour}:${pad schedule.minute}"
          "${pad (schedule.hour + 12)}:${pad schedule.minute}"
        ];
      description = "备份快照的日历时间（HH:MM），默认每天两次，按 hostname 均匀分布";
      example = [
        "2:30"
        "14:45"
      ];
    };
    policySyncWhen = lib.mkOption {
      type = lib.types.str;
      default = "5:00";
      description = "周日策略同步的日历时间（HH:MM）";
      example = "5:00";
    };
    policy = lib.mkOption {
      type = lib.types.submodule {
        options = {
          compression = lib.mkOption {
            type = lib.types.str;
            default = policyDefaults.compression;
            description = "压缩算法";
            example = "zstd-fastest";
          };
          ignores = lib.mkOption {
            type = with lib.types; listOf str;
            default = policyDefaults.ignores;
            description = "忽略模式列表";
            example = [
              "*.tmp"
              "node_modules"
              "*.log"
            ];
          };
          retention = lib.mkOption {
            type = with lib.types; attrsOf lib.types.int;
            default = policyDefaults.retention;
            description = "保留策略";
            example = {
              latest = 24;
              daily = 7;
              weekly = 4;
            };
          };
        };
      };
      default = policyDefaults;
      description = ''
        本机备份策略，固定应用于 <user>@<host> 目标，默认值见 ./_policy-defaults.nix。
        用户级额外忽略模式见 modules/features/backup/backup-options.nix 的 ignores。
      '';
      example = {
        retention = {
          daily = 30;
        };
      };
    };
  };
}
