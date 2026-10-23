# macOS 系统基础：PAM/sudo、时区、system defaults、键盘、快捷键禁用
# 所有 darwin 主机都需要 → darwin.core
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.system ];

  flake.modules.darwin.system.imports = [
    ./_settings.nix
    ./_hotkeys.nix
  ];
}
