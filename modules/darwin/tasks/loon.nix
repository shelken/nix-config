# 定时任务约定见同目录 gc.nix 头部注释
{
  lib,
  config,
  mylib,
  ...
}:
let
  cfg = config.shelken.tasks.loon;
  logDir = "/Library/Application Support/com.loon.Loon/tunnelLog";
in
{
  options.shelken.tasks.loon = {
    enable = mylib.mkBoolOpt false "定时清理 Loon 隧道日志（仅保留最新一份）";

    interval = lib.mkOption {
      type = lib.types.int;
      default = 7200;
      description = "launchd StartInterval（秒）";
    };
  };

  config = lib.mkIf cfg.enable {
    # 日志文件属主为 root，必须以 root daemon 运行（用户态 sudo 无法交互）
    launchd.daemons.clean-loon-logs = {
      script = ''
        cd "${logDir}" 2>/dev/null || exit 0
        ls -t | tail -n +2 | while IFS= read -r f; do rm -f -- "$f"; done
      '';
      serviceConfig = {
        RunAtLoad = true;
        KeepAlive = false;
        StartInterval = cfg.interval;
      };
    };
  };
}
