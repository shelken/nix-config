{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.shelken.sessionArchive;
  roots = lib.concatLists (lib.attrValues cfg.app);

  # coreutils 排在 PATH 最前：交互 shell 里的 rm 可能被替换成回收站，归档必须真删
  archive = pkgs.writeShellApplication {
    name = "session-archive";
    runtimeInputs = with pkgs; [
      age
      zstd
      coreutils
      findutils
      diffutils
    ];
    runtimeEnv = {
      SESSION_ARCHIVE_ROOTS = lib.concatStringsSep "\n" roots;
      SESSION_ARCHIVE_DAYS = toString cfg.afterDays;
      SESSION_ARCHIVE_KEY_FILE = cfg.keyFile;
    };
    text = builtins.readFile ./session-archive.sh;
  };
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = config.shelken.secrets.enable;
          message = "shelken.sessionArchive: 归档需要主机启用 secrets (shelken.secrets.enable = true)，加密用 sops 的 age 密钥";
        }
        {
          assertion = builtins.all (p: lib.hasPrefix "/" p) roots;
          message = "shelken.sessionArchive: 所有会话目录必须是绝对路径（以 / 开头），请检查 shelken.sessionArchive.app 的配置";
        }
      ];
    }

    # 没有任何 app 声明目录时不装任务，也不装命令
    (lib.mkIf (roots != [ ]) {
      home.packages = [ archive ];

      # 失败时原文件保留、不会损失数据，只写任务日志，不发通知
      shelken.tasks.session-archive = {
        when = "4:20";
        packages = [ archive ];
        notify.failure = false;
        script = "session-archive run";
      };
    })
  ];
}
