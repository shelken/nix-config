# 声明式定时任务框架（shelken.tasks 选项 + hosts/<host>/tasks 自动发现）与全设备默认任务
# 规则见 docs/adr/0001 与 .agents/skills/create-task/；所有 darwin 主机都需要 → darwin.core
{ config, lib, ... }:
let
  # 全设备任务：_global/ 下的每个 .nix 都是一个 darwin 模块，放文件即注册。
  # 目录带 _ 前缀，import-tree 不会把它们当成 flake-parts 模块导入
  globalTasks = lib.mapAttrsToList (name: _: ./_global + "/${name}") (
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
      builtins.readDir ./_global
    )
  );
in
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tasks ];

  flake.modules.darwin.tasks.imports = [ ./_framework.nix ] ++ globalTasks;

  flake.modules.homeManager.tasks.imports = [
    ./_user-tasks.nix
    ./_notify.nix
  ];
}
