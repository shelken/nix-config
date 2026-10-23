# shell/ssh/git 的 darwin 补充：Homebrew 路径、orbstack 初始化、quarantine 清除别名
# 所有 darwin 主机都需要 → darwin.core（经同名挂接进 HM）
{ config, ... }:
{
  flake.modules.darwin.core.imports = [ config.flake.modules.darwin.shell ];

  flake.modules.homeManager.shell.imports = [ ./_hm.nix ];
}
