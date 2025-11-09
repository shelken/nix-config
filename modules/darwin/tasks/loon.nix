# ref: https://nix-darwin.github.io/nix-darwin/manual/#opt-launchd.user.agents
{
  mylib,
  lib,
  config,
  ...
}:
let
  cfg = config.shelken.tasks.loon;
  # 保留 loon 最新日志，其他全部删除
  script = ''
    #!/usr/bin/env bash
    LOON_LOG_PATH=/Users/Shared/com.loon.Loon/tunnelLog
    /bin/ls -t $LOON_LOG_PATH | tail -n +2 | sudo xargs -I {} rm $LOON_LOG_PATH/{}
  '';
in
{
  options.shelken.tasks.loon = {
    enable = mylib.mkBoolOpt false "Whether or not use to enable.";
  };
  config = lib.mkIf cfg.enable {
    launchd.agents.clean-loon-logs = {
      inherit script;
      serviceConfig = {
        Label = "space.ooooo.clean-loon-logs";
        RunAtLoad = true;
        KeepAlive = false;
        StartInterval = 7200; # 2h 清理一次
        EnvironmentVariables = {
        };
        StandardErrorPath = "/Library/Logs/space.ooooo.clean-loon-logs.stderr.log";
      };
    };
  };
}
