{
  config,
  lib,
  pkgs,
  mylib,
  myvars,
  ...
}:
let
  taskCfg = config.shelken.tasks;
  userSops = config.home-manager.users.${myvars.username}.sops;

  tasksLib = mylib.mkTasksLib {
    inherit lib pkgs;
    homeDir = userHome;
    opTokenFile = userSops.secrets."op/service-account-token".path;
  };

  userHome = config.users.users.${myvars.username}.home;

  taskType = tasksLib.mkTaskType;
in
{
  options.shelken.tasks = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule taskType);
    default = { };
    description = "声明式定时任务，任务文件在 hosts/<host>/tasks/ 下自动加载";
  };

  config =
    let
      rootTasks = tasksLib.rootTasks taskCfg;
    in
    {
      shelken.tasks = mylib.loadTasks (mylib.relativeToRoot "hosts/${config.networking.hostName}/tasks") {
        inherit pkgs lib;
        secretPath = secret: userSops.secrets.${secret}.path;
      };

      assertions = tasksLib.mkAssertions taskCfg;

      launchd.daemons = lib.mapAttrs (name: t: {
        command = "${t.package}/bin/task-${name}";
        serviceConfig = tasksLib.mkLaunchdConfig name t;
      }) rootTasks;

      # launchd 每次启动任务都会重新打开日志，标志 N 避免 newsyslog 轮转后向 syslogd 发 SIGHUP
      environment.etc."newsyslog.d/space.ooooo.tasks.conf".text = ''
        /Library/Logs/task-*.log               root:wheel                  644  5     1024     *    GNZ
        ${userHome}/Library/Logs/task-*.log    ${myvars.username}:staff    644  5     1024     *    GNZ
      '';

      environment.systemPackages = lib.attrValues (lib.mapAttrs (_: t: t.package) rootTasks);
    };
}
