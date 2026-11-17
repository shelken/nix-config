# Ansible 部署工具与 sshpass
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.ansible ];

  flake.modules.homeManager.ansible =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ansible
        ansible-lint
        sshpass
      ];
    };
}
