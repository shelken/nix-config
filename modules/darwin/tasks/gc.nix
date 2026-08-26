# 定时任务约定：
# - 用户权限任务放 home/darwin/tasks/（home-manager launchd.agents）
# - root 权限任务放本目录（nix-darwin launchd.daemons）
# - 统一形状：shelken.tasks.<name>.{ enable, interval }，hosts 层覆盖 interval
# - StartCalendarInterval 睡眠错过会在唤醒后补跑（合并一次）
{
  lib,
  config,
  mylib,
  ...
}:
let
  cfg = config.shelken.tasks.gc;
in
{
  options.shelken.tasks.gc = {
    enable = mylib.mkBoolOpt true "自动垃圾回收（删除 7d 前的旧 generations）";

    interval = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.int);
      default = [
        {
          Hour = 3;
          Minute = 15;
        }
      ];
      description = "launchd StartCalendarInterval";
    };
  };

  config = lib.mkIf cfg.enable {
    # nix.gc.automatic 会被 nix-darwin 断言拒绝（requires nix.enable，
    # 与 Determinate Nix 冲突），故直接定义等价 daemon
    launchd.daemons.nix-gc = {
      command = "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 7d";
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = cfg.interval;
      };
    };
  };
}
