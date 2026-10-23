# 声明式定时任务框架（shelken.tasks 选项 + hosts/<host>/tasks 自动发现）与全设备默认任务
# 规则见 docs/adr/0001 与 .agents/skills/create-task/；所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.tasks ];

  flake.modules.darwin.tasks.imports = [
    ./_framework.nix
    ./_gc.nix
  ];

  flake.modules.homeManager.tasks.imports = [ ./_user-tasks.nix ];
}
