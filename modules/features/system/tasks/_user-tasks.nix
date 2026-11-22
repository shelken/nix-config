{
  config,
  lib,
  pkgs,
  mylib,
  hostname,
  ...
}:
let
  tasksLib = mylib.mkTasksLib {
    inherit lib pkgs;
    homeDir = config.home.homeDirectory;
    secretsEnabled = config.shelken.secrets.enable;
    opTokenFile =
      if config.shelken.secrets.enable then config.sops.secrets."op/service-account-token".path else null;
  };

  taskCfg = config.shelken.tasks;
  userTasks = tasksLib.userTasks taskCfg;

  taskCli = pkgs.writers.writePython3Bin "ntask" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings [ "@labelPrefix@" ] [ tasksLib.labelPrefix ] (
      builtins.readFile ./_cli/task.py
    )
  );
  taskCompletion = pkgs.writeTextDir "share/zsh/site-functions/_ntask" (
    builtins.readFile ./_cli/_ntask
  );
in
{
  options.shelken.tasks = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule tasksLib.mkTaskType);
    default = { };
    description = "声明式定时任务；hosts/<hostname>/tasks/ 自动加载，feature 模块可直接声明";
  };

  config = {
    shelken.tasks = lib.filterAttrs (_: t: t.user or true) (
      mylib.loadTasks (mylib.relativeToRoot "hosts/${hostname}/tasks") {
        inherit pkgs lib;
        secretPath = tasksLib.mkSecretPath (secret: config.sops.secrets.${secret}.path);
      }
    );

    assertions = tasksLib.mkAssertions taskCfg ++ [
      {
        assertion = lib.all (t: t.user) (lib.attrValues taskCfg);
        message = "shelken.tasks: Home Manager 层的任务必须 user = true；root 任务写到 hosts/<机器>/tasks/ 或功能的 darwin 模块";
      }
    ];

    launchd.agents = lib.mapAttrs (
      name: t:
      mylib.mkLaunchCommand {
        name = "task-${name}";
        commandFile = "${t.package}/bin/task-${name}";
        # 始终 user domain：任务执行不与图形会话绑定（gui domain 在无图形登录时不运行）
        domain = "user";
        config = tasksLib.mkLaunchdConfig name t;
      }
    ) userTasks;

    home.packages = (lib.mapAttrsToList (_: t: t.package) userTasks) ++ [
      taskCli
      taskCompletion
    ];
  };
}
