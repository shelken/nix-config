# OrbStack：容器与 Linux 虚拟机；shell 初始化随应用本体
{ config, ... }:
{
  flake.modules.darwin.desktop.imports = [ config.flake.modules.darwin.orbstack ];

  flake.modules.darwin.orbstack.homebrew.casks = [ "orbstack" ];

  flake.modules.homeManager.orbstack = {
    programs.bash.profileExtra = ''
      source ~/.orbstack/shell/init.bash 2>/dev/null || true
    '';
    programs.zsh.profileExtra = ''
      source ~/.orbstack/shell/init.zsh 2>/dev/null || true
    '';
  };
}
