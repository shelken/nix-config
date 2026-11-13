# tasks 用户态部分：用户 launch agents、task CLI 与主机任务发现
# hosts/<host>/tasks/ 中的任务与 feature 模块声明的 shelken.tasks.<name> 汇总到
# 同一份选项：user 任务生成 LaunchAgent + task-<name> 手动命令。
#
# 为什么在 home 层：两个 HM 入口（just sw 内嵌 / just hm 独立）共同持有
# 用户态 agent，任一入口切换都不会清理另一入口部署的 agent
# （否则独立 just hm 会把 sw 生成的 profile-usage agent 删掉）。
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
  };

  taskCfg = config.shelken.tasks;
  userTasks = tasksLib.userTasks taskCfg;

  # 标签前缀只在 lib/tasks.nix 定义一次，构建时注入 CLI
  taskCli = pkgs.writers.writePython3Bin "task" { flakeIgnore = [ "E501" ]; } (
    builtins.replaceStrings [ "@labelPrefix@" ] [ tasksLib.labelPrefix ] (
      builtins.readFile ./_cli/task.py
    )
  );
  taskCompletion = pkgs.writeTextDir "share/zsh/site-functions/_task" (
    builtins.readFile ./_cli/_task
  );
in
{
  options.shelken.tasks = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule tasksLib.mkTaskType);
    default = { };
    description = "声明式定时任务；hosts/<hostname>/tasks/ 自动加载，feature 模块可直接声明";
  };

  config = {
    # 约定优于配置：hosts/<hostname>/tasks/ 自动加载，目录存在即接入，host 文件无需接线。
    # 只取 user 任务，root 任务由 darwin 层从同一目录另行加载
    shelken.tasks = lib.filterAttrs (_: t: t.user or true) (
      mylib.loadTasks (mylib.relativeToRoot "hosts/${hostname}/tasks") {
        inherit pkgs lib;
        secretPath = secret: config.sops.secrets.${secret}.path;
      }
    );

    assertions = tasksLib.mkAssertions taskCfg ++ [
      # 用户层只生成 LaunchAgent，root 任务在这里会被静默丢弃，改成构建期报错
      {
        assertion = lib.all (t: t.user) (lib.attrValues taskCfg);
        message = "shelken.tasks: Home Manager 层的任务必须 user = true；root 任务写到 hosts/<机器>/tasks/ 或 modules/features/darwin/tasks/_global/";
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
