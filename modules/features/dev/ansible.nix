# Ansible 部署工具与 sshpass
# 开发机 → tui
{ config, ... }:
{
  flake.modules.homeManager.tui.imports = [ config.flake.modules.homeManager.ansible ];

  flake.modules.homeManager.ansible =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # ansible（= ansible-core）不带 collections；ansible-lint 会把全量 ansible（约 520 MiB）作为依赖拉进来，不装
        ansible
        sshpass
      ];
    };
}
