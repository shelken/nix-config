# 集成开发环境（IntelliJ IDEA）
{ config, ... }:
{
  flake.modules.darwin.workstation.imports = [ config.flake.modules.darwin.ide ];

  flake.modules.darwin.ide.homebrew.casks = [ "intellij-idea" ];
}
